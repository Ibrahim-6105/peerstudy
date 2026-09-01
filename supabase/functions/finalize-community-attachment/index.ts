// Verify real private Storage bytes before one Community attachment is visible.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import {
  ApiError,
  authenticate,
  errorResponse,
  jsonResponse,
  preflightResponse,
  readJsonObject,
  requestId,
  requireActiveStudent,
  requireUuid,
} from "../_shared/http.ts";
import {
  attachmentSizeLimit,
  findAttachment,
  requireOwnedActiveTarget,
  sha256Hex,
  validateAttachmentBytes,
} from "../_shared/community_attachment.ts";

// Terminal size/type/signature failures close the reservation immediately.  A
// conditional status update prevents this cleanup from deleting an object that
// another finalizer already changed to ready.
async function rejectInvalidUpload(
  service: SupabaseClient,
  attachmentId: string,
  storagePath: string,
  userId: string,
): Promise<void> {
  const { data, error } = await service
    .from("community_attachments")
    .update({
      status: "removed",
      removal_reason: "Uploaded bytes failed attachment validation",
      removed_at: new Date().toISOString(),
      removed_by: userId,
    })
    .eq("id", attachmentId)
    .eq("status", "uploading")
    .select("id");
  if (error) {
    throw new ApiError(
      503,
      "Invalid attachment state could not be closed.",
      "attachment-database-unavailable",
    );
  }
  if ((data ?? []).length === 1) {
    // Metadata is already hidden if physical deletion temporarily fails.  The
    // protected cleanup function can safely retry this exact removed row.
    const { error: removeError } = await service.storage
      .from("community-attachments")
      .remove([storagePath]);
    if (!removeError) {
      await service
        .from("community_attachments")
        .update({ storage_deleted_at: new Date().toISOString() })
        .eq("id", attachmentId)
        .eq("status", "removed");
    }
  }
}

// Distinguish a definite missing object from a temporary Storage failure.  The
// Flutter retry flow uploads only for the definite missing-object code.
function isObjectMissing(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const row = error as Record<string, unknown>;
  const status = String(row.statusCode ?? row.status ?? "");
  const message = String(row.message ?? row.error ?? "").toLowerCase();
  return status === "404" || message.includes("object not found") ||
    message.includes("not_found");
}

Deno.serve(async (request) => {
  const correlationId = requestId(request);
  try {
    const preflight = preflightResponse(request);
    if (preflight) return preflight;

    const { service, user } = await authenticate(request);
    await requireActiveStudent(service, user.id);
    const body = await readJsonObject(request);
    const attachmentId = requireUuid(body.attachment_id, "attachment_id");

    const attachment = await findAttachment(service, attachmentId);
    if (!attachment) {
      throw new ApiError(
        404,
        "Attachment reservation was not found.",
        "attachment-not-found",
      );
    }
    await requireOwnedActiveTarget(service, attachment, user.id);

    // An Edge response may be lost after completion; return the authoritative
    // row without downloading or hashing the immutable object again.
    if (attachment.status === "ready") {
      return jsonResponse(request, { attachment }, 200);
    }
    if (attachment.status !== "uploading") {
      throw new ApiError(
        409,
        "This attachment reservation is no longer usable.",
        "attachment-reservation-closed",
      );
    }

    // Reservations have the same thirty-minute lifetime enforced by SQL.  Mark
    // a stale row removed before deleting its possible inaccessible byte.
    const createdAt = Date.parse(attachment.created_at);
    if (
      !Number.isFinite(createdAt) || Date.now() - createdAt >= 30 * 60 * 1000
    ) {
      const { data: expired, error: expireError } = await service
        .from("community_attachments")
        .update({
          status: "removed",
          removal_reason: "Upload reservation expired",
          removed_at: new Date().toISOString(),
          removed_by: null,
        })
        .eq("id", attachment.id)
        .eq("status", "uploading")
        .select("id");
      if (expireError) {
        throw new ApiError(
          503,
          "Attachment expiration could not be saved.",
          "attachment-database-unavailable",
        );
      }
      // Delete only when this request actually won the uploading-to-removed
      // race.  A concurrent successful completion must keep its ready byte.
      if ((expired ?? []).length === 1) {
        const { error: removeError } = await service.storage
          .from("community-attachments")
          .remove([attachment.storage_path]);
        if (!removeError) {
          await service
            .from("community_attachments")
            .update({ storage_deleted_at: new Date().toISOString() })
            .eq("id", attachment.id)
            .eq("status", "removed");
        }
      }
      throw new ApiError(
        409,
        "Attachment reservation expired. Select the file again.",
        "attachment-reservation-expired",
      );
    }

    const { data: blob, error: downloadError } = await service.storage
      .from("community-attachments")
      .download(attachment.storage_path);
    if (downloadError) {
      if (isObjectMissing(downloadError)) {
        throw new ApiError(
          404,
          "The reserved attachment has not been uploaded.",
          "attachment-object-missing",
        );
      }
      throw new ApiError(
        503,
        "Attachment Storage is temporarily unavailable.",
        "attachment-storage-unavailable",
      );
    }
    if (!blob) {
      throw new ApiError(
        503,
        "Attachment Storage returned no file.",
        "attachment-storage-unavailable",
      );
    }

    const recordedSize = Number(attachment.size_bytes);
    if (
      !Number.isSafeInteger(recordedSize) || recordedSize < 1 ||
      recordedSize > attachmentSizeLimit || blob.size !== recordedSize
    ) {
      await rejectInvalidUpload(
        service,
        attachment.id,
        attachment.storage_path,
        user.id,
      );
      throw new ApiError(
        409,
        "Uploaded attachment size does not match its reservation.",
        "attachment-integrity-failed",
      );
    }

    const bytes = new Uint8Array(await blob.arrayBuffer());
    if (bytes.byteLength !== recordedSize) {
      await rejectInvalidUpload(
        service,
        attachment.id,
        attachment.storage_path,
        user.id,
      );
      throw new ApiError(
        409,
        "Uploaded attachment size does not match its reservation.",
        "attachment-integrity-failed",
      );
    }
    const storedMime = blob.type.toLowerCase().split(";", 1)[0].trim();
    if (storedMime !== attachment.mime_type) {
      await rejectInvalidUpload(
        service,
        attachment.id,
        attachment.storage_path,
        user.id,
      );
      throw new ApiError(
        409,
        "Stored attachment type does not match its reservation.",
        "attachment-integrity-failed",
      );
    }
    try {
      validateAttachmentBytes(bytes, attachment.mime_type);
    } catch (error) {
      if (
        error instanceof ApiError &&
        error.code === "attachment-integrity-failed"
      ) {
        await rejectInvalidUpload(
          service,
          attachment.id,
          attachment.storage_path,
          user.id,
        );
      }
      throw error;
    }
    const checksum = await sha256Hex(bytes);

    // This server-only RPC takes the row lock, rechecks the active hierarchy,
    // records the trusted checksum, and atomically changes uploading to ready.
    const { data: completed, error: completeError } = await service.rpc(
      "complete_community_attachment",
      { p_attachment_id: attachment.id, p_checksum: checksum },
    );
    if (completeError || !completed) {
      throw new ApiError(
        409,
        "Attachment could not be completed because its state changed.",
        "attachment-completion-conflict",
      );
    }
    const completedRow = Array.isArray(completed)
      ? completed.length === 1 ? completed[0] : null
      : completed;
    if (!completedRow || typeof completedRow !== "object") {
      throw new ApiError(
        503,
        "Attachment completion returned an invalid result.",
        "attachment-database-unavailable",
      );
    }

    return jsonResponse(request, { attachment: completedRow }, 200);
  } catch (error) {
    return errorResponse(request, error, correlationId);
  }
});
