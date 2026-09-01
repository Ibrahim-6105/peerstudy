// Shared validation for private Community attachment Edge Functions.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import { ApiError, requireActiveSubject } from "./http.ts";

// The database and private Storage bucket enforce the same ten-MiB ceiling.
export const attachmentSizeLimit = 10 * 1024 * 1024;

// This is the complete row shape returned to the Flutter attachment model.
export interface CommunityAttachmentRow {
  id: string;
  post_id: string | null;
  comment_id: string | null;
  uploaded_by: string;
  file_name: string;
  storage_path: string;
  mime_type: string;
  size_bytes: number;
  checksum: string | null;
  status: "uploading" | "ready" | "removed";
  idempotency_key: string;
  removal_reason: string | null;
  removed_at: string | null;
  removed_by: string | null;
  storage_deleted_at: string | null;
  created_at: string;
  updated_at: string;
}

// Select all fields explicitly so server responses cannot accidentally include
// a future private database column.
export const attachmentColumns =
  "id, post_id, comment_id, uploaded_by, file_name, storage_path, mime_type, " +
  "size_bytes, checksum, status, idempotency_key, removal_reason, removed_at, " +
  "removed_by, storage_deleted_at, created_at, updated_at";

// Load one metadata row with the server client.  Callers still perform their
// own operation-specific ownership/status checks before touching its bytes.
export async function findAttachment(
  service: SupabaseClient,
  attachmentId: string,
): Promise<CommunityAttachmentRow | null> {
  const { data, error } = await service
    .from("community_attachments")
    .select(attachmentColumns)
    .eq("id", attachmentId)
    .maybeSingle();

  if (error) {
    throw new ApiError(
      503,
      "Attachment state could not be checked.",
      "attachment-check-failed",
    );
  }
  return data as CommunityAttachmentRow | null;
}

// Prove that the caller authored the exact active target and that its complete
// School hierarchy is active.  This mirrors the SQL reservation policy and is
// rechecked immediately before finalization.
export async function requireOwnedActiveTarget(
  service: SupabaseClient,
  attachment: CommunityAttachmentRow,
  userId: string,
): Promise<void> {
  if (attachment.uploaded_by !== userId) {
    throw new ApiError(
      403,
      "Only the attachment author may use this upload.",
      "attachment-not-owned",
    );
  }

  let subjectId = "";
  if (attachment.post_id) {
    const { data: post, error } = await service
      .from("community_posts")
      .select("id, community_id, author_id, status")
      .eq("id", attachment.post_id)
      .maybeSingle();
    if (
      error || !post || post.status !== "active" || post.author_id !== userId
    ) {
      throw new ApiError(
        409,
        "The attachment Post is no longer available.",
        "attachment-target-unavailable",
      );
    }
    // Corrected-master guarantees Community ID equals Subject ID.
    subjectId = String(post.community_id);
  } else if (attachment.comment_id) {
    const { data: comment, error: commentError } = await service
      .from("community_comments")
      .select("id, post_id, author_id, status")
      .eq("id", attachment.comment_id)
      .maybeSingle();
    if (
      commentError || !comment || comment.status !== "active" ||
      comment.author_id !== userId
    ) {
      throw new ApiError(
        409,
        "The attachment Comment is no longer available.",
        "attachment-target-unavailable",
      );
    }

    const { data: post, error: postError } = await service
      .from("community_posts")
      .select("id, community_id, status")
      .eq("id", comment.post_id)
      .maybeSingle();
    if (postError || !post || post.status !== "active") {
      throw new ApiError(
        409,
        "The parent Post is no longer available.",
        "attachment-target-unavailable",
      );
    }
    subjectId = String(post.community_id);
  } else {
    throw new ApiError(
      409,
      "The attachment target is invalid.",
      "attachment-target-unavailable",
    );
  }

  await requireActiveSubject(service, subjectId);
}

// Compare a small byte prefix without converting untrusted binary data to text.
function startsWith(bytes: Uint8Array, expected: number[]): boolean {
  if (bytes.length < expected.length) return false;
  return expected.every((value, index) => bytes[index] === value);
}

// Compare an exact byte suffix.  PNG uses this for its required IEND trailer.
function endsWith(bytes: Uint8Array, expected: number[]): boolean {
  if (bytes.length < expected.length) return false;
  const offset = bytes.length - expected.length;
  return expected.every((value, index) => bytes[offset + index] === value);
}

// Reject a MIME-label-only upload.  Every allowed format must have its actual
// signature/structure checked before SQL can transition it to ready.
export function validateAttachmentBytes(
  bytes: Uint8Array,
  mimeType: string,
): void {
  if (bytes.length < 1 || bytes.length > attachmentSizeLimit) {
    throw new ApiError(
      409,
      "Uploaded attachment size is invalid.",
      "attachment-integrity-failed",
    );
  }

  let valid = false;
  if (mimeType === "image/jpeg") {
    const hasHeader = startsWith(bytes, [0xff, 0xd8, 0xff]);
    const tailStart = Math.max(0, bytes.length - 32);
    let hasEndMarker = false;
    for (let index = tailStart; index + 1 < bytes.length; index += 1) {
      if (bytes[index] === 0xff && bytes[index + 1] === 0xd9) {
        hasEndMarker = true;
        break;
      }
    }
    valid = hasHeader && hasEndMarker;
  } else if (mimeType === "image/png") {
    valid = startsWith(bytes, [137, 80, 78, 71, 13, 10, 26, 10]) &&
      endsWith(bytes, [0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);
  } else if (mimeType === "image/webp") {
    if (
      bytes.length >= 20 && startsWith(bytes, [82, 73, 70, 70]) &&
      bytes[8] === 87 && bytes[9] === 69 && bytes[10] === 66 &&
      bytes[11] === 80
    ) {
      const declaredLength = bytes[4] | (bytes[5] << 8) |
        (bytes[6] << 16) | (bytes[7] << 24);
      const chunk = String.fromCharCode(...bytes.subarray(12, 16));
      valid = (declaredLength >>> 0) + 8 === bytes.length &&
        (chunk === "VP8 " || chunk === "VP8L" || chunk === "VP8X");
    }
  } else if (mimeType === "application/pdf") {
    const hasHeader = startsWith(bytes, [37, 80, 68, 70, 45]);
    const tail = new TextDecoder("ascii").decode(
      bytes.subarray(Math.max(0, bytes.length - 1024)),
    );
    valid = hasHeader && tail.includes("%%EOF");
  } else if (mimeType === "text/plain") {
    try {
      const decoded = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
      // Permit tab/newline/carriage-return but reject NUL and other controls.
      valid = !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(decoded);
    } catch {
      valid = false;
    }
  }

  if (!valid) {
    throw new ApiError(
      409,
      "Uploaded bytes do not match the selected attachment type.",
      "attachment-integrity-failed",
    );
  }
}

// The digest stored in PostgreSQL is always computed from verified server bytes.
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  // Copy into a plain ArrayBuffer accepted by the Web Crypto BufferSource type.
  const digest = await crypto.subtle.digest(
    "SHA-256",
    Uint8Array.from(bytes).buffer,
  );
  return Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}
