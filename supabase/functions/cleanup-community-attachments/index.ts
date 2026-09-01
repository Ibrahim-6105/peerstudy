// Permanently clean private bytes after Community attachment metadata is hidden.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import {
  ApiError,
  authenticate,
  errorResponse,
  jsonResponse,
  preflightResponse,
  readJsonObject,
  requestId,
  requireUuid,
} from "../_shared/http.ts";
import {
  attachmentColumns,
  type CommunityAttachmentRow,
  findAttachment,
} from "../_shared/community_attachment.ts";

type ActiveProfile = {
  id: string;
  role: "student" | "admin";
  status: "active";
};

// A restricted account cannot delete retained moderation evidence.  Active
// Admins can clean any hidden bytes, while active Students stay owner-scoped.
async function requireActiveProfile(
  service: SupabaseClient,
  userId: string,
): Promise<ActiveProfile> {
  const { data, error } = await service
    .from("profiles")
    .select("id, role, status")
    .eq("id", userId)
    .maybeSingle();
  if (error) {
    throw new ApiError(
      503,
      "The account could not be verified.",
      "profile-check-failed",
    );
  }
  if (
    !data || data.status !== "active" ||
    (data.role !== "student" && data.role !== "admin")
  ) {
    throw new ApiError(
      403,
      "This account cannot clean Community attachments.",
      "account-restricted",
    );
  }
  return data as ActiveProfile;
}

// Return the parent Post author for a direct Post or Comment attachment.
async function parentPostAuthor(
  service: SupabaseClient,
  attachment: CommunityAttachmentRow,
): Promise<string | null> {
  let postId = attachment.post_id;
  if (!postId && attachment.comment_id) {
    const { data: comment } = await service
      .from("community_comments")
      .select("post_id")
      .eq("id", attachment.comment_id)
      .maybeSingle();
    postId = comment?.post_id ?? null;
  }
  if (!postId) return null;
  const { data: post } = await service
    .from("community_posts")
    .select("author_id")
    .eq("id", postId)
    .maybeSingle();
  return post?.author_id ?? null;
}

// Fetch only hidden/incomplete rows.  Ready attachments are deliberately never
// returned by this cleanup path, even to an Admin.
async function cleanupCandidatesForIds(
  service: SupabaseClient,
  ids: string[],
): Promise<CommunityAttachmentRow[]> {
  if (ids.length === 0) return [];
  const { data, error } = await service
    .from("community_attachments")
    .select(attachmentColumns)
    .in("id", ids)
    .in("status", ["uploading", "removed"])
    .is("storage_deleted_at", null)
    .limit(200);
  if (error) {
    throw new ApiError(
      503,
      "Attachment cleanup state could not be read.",
      "attachment-check-failed",
    );
  }
  return (data ?? []) as unknown as CommunityAttachmentRow[];
}

Deno.serve(async (request) => {
  const correlationId = requestId(request);
  try {
    const preflight = preflightResponse(request);
    if (preflight) return preflight;

    const { service, user } = await authenticate(request);
    const profile = await requireActiveProfile(service, user.id);
    const body = await readJsonObject(request);
    const suppliedAttachmentId = body.attachment_id;
    const suppliedTargetType = typeof body.target_type === "string"
      ? body.target_type.trim().toLowerCase()
      : "";
    const suppliedTargetId = body.target_id;
    const suppliedOwnRemoved = body.own_removed;

    const usesAttachment = suppliedAttachmentId !== undefined;
    const usesTarget = suppliedTargetType !== "" ||
      suppliedTargetId !== undefined;
    const usesOwnerSweep = suppliedOwnRemoved === true;
    if (
      suppliedOwnRemoved !== undefined && suppliedOwnRemoved !== true
    ) {
      throw new ApiError(
        400,
        "own_removed must be true when supplied.",
        "invalid-argument",
      );
    }
    const selectorCount = Number(usesAttachment) + Number(usesTarget) +
      Number(usesOwnerSweep);
    if (selectorCount !== 1) {
      throw new ApiError(
        400,
        "Send one attachment, one target, or own_removed cleanup selector.",
        "invalid-argument",
      );
    }

    let candidates: CommunityAttachmentRow[] = [];
    if (usesAttachment) {
      const attachmentId = requireUuid(suppliedAttachmentId, "attachment_id");
      const attachment = await findAttachment(service, attachmentId);
      if (!attachment) {
        throw new ApiError(
          404,
          "Attachment was not found.",
          "attachment-not-found",
        );
      }
      const postAuthor = await parentPostAuthor(service, attachment);
      // A parent Post author may clean a Comment author's byte only after the
      // database has already hidden it.  Only the uploader/Admin may cancel an
      // in-progress uploading reservation directly.
      const authorized = profile.role === "admin" ||
        attachment.uploaded_by === user.id ||
        (attachment.status === "removed" && postAuthor === user.id);
      if (!authorized) {
        throw new ApiError(
          403,
          "You cannot clean this attachment.",
          "attachment-not-owned",
        );
      }
      candidates = await cleanupCandidatesForIds(service, [attachment.id]);
    } else if (usesOwnerSweep) {
      // A normal upload starts with this bounded sweep so interrupted or
      // abandoned reservations cannot permanently consume the Student quota.
      const cutoff = new Date(Date.now() - 30 * 60 * 1000).toISOString();
      const { data: staleRows, error: staleError } = await service
        .from("community_attachments")
        .select("id")
        .eq("uploaded_by", user.id)
        .eq("status", "uploading")
        .lt("created_at", cutoff)
        .is("storage_deleted_at", null)
        .limit(200);
      if (staleError) {
        throw new ApiError(
          503,
          "Stale attachment state could not be read.",
          "attachment-check-failed",
        );
      }
      const candidateIds = (staleRows ?? []).map((row) => String(row.id));
      if (candidateIds.length < 200) {
        const { data: removedRows, error: removedError } = await service
          .from("community_attachments")
          .select("id")
          .eq("uploaded_by", user.id)
          .eq("status", "removed")
          .is("storage_deleted_at", null)
          .limit(200 - candidateIds.length);
        if (removedError) {
          throw new ApiError(
            503,
            "Removed attachment state could not be read.",
            "attachment-check-failed",
          );
        }
        candidateIds.push(
          ...(removedRows ?? []).map((row) => String(row.id)),
        );
      }
      candidates = await cleanupCandidatesForIds(
        service,
        Array.from(new Set(candidateIds)),
      );
    } else {
      const targetId = requireUuid(suppliedTargetId, "target_id");
      if (suppliedTargetType !== "post" && suppliedTargetType !== "comment") {
        throw new ApiError(
          400,
          "target_type must be post or comment.",
          "invalid-argument",
        );
      }

      const candidateIds: string[] = [];
      if (suppliedTargetType === "post") {
        const { data: post, error: postError } = await service
          .from("community_posts")
          .select("id, author_id, status")
          .eq("id", targetId)
          .maybeSingle();
        if (postError || !post) {
          throw new ApiError(404, "Post was not found.", "target-not-found");
        }
        if (post.status !== "removed") {
          throw new ApiError(
            409,
            "Remove the Post before cleaning its attachments.",
            "target-still-active",
          );
        }
        if (profile.role !== "admin" && post.author_id !== user.id) {
          throw new ApiError(
            403,
            "Only the Post author or an Admin may clean this thread.",
            "target-not-owned",
          );
        }

        const { data: comments, error: commentError } = await service
          .from("community_comments")
          .select("id")
          .eq("post_id", targetId)
          .limit(1000);
        if (commentError) {
          throw new ApiError(
            503,
            "Comment cleanup state could not be read.",
            "attachment-check-failed",
          );
        }
        const commentIds = (comments ?? []).map((row) => String(row.id));

        const { data: directRows, error: directError } = await service
          .from("community_attachments")
          .select("id")
          .eq("post_id", targetId)
          .eq("status", "removed")
          .is("storage_deleted_at", null)
          .limit(200);
        if (directError) {
          throw new ApiError(
            503,
            "Post attachment cleanup state could not be read.",
            "attachment-check-failed",
          );
        }
        candidateIds.push(...(directRows ?? []).map((row) => String(row.id)));

        if (commentIds.length > 0 && candidateIds.length < 200) {
          const { data: commentRows, error: attachmentError } = await service
            .from("community_attachments")
            .select("id")
            .in("comment_id", commentIds)
            .eq("status", "removed")
            .is("storage_deleted_at", null)
            .limit(200 - candidateIds.length);
          if (attachmentError) {
            throw new ApiError(
              503,
              "Comment attachment cleanup state could not be read.",
              "attachment-check-failed",
            );
          }
          candidateIds.push(
            ...(commentRows ?? []).map((row) => String(row.id)),
          );
        }
      } else {
        const { data: comment, error: commentError } = await service
          .from("community_comments")
          .select("id, post_id, author_id, status")
          .eq("id", targetId)
          .maybeSingle();
        if (commentError || !comment) {
          throw new ApiError(
            404,
            "Comment was not found.",
            "target-not-found",
          );
        }
        if (comment.status !== "removed") {
          throw new ApiError(
            409,
            "Remove the Comment before cleaning its attachments.",
            "target-still-active",
          );
        }
        const { data: post, error: postError } = await service
          .from("community_posts")
          .select("author_id")
          .eq("id", comment.post_id)
          .maybeSingle();
        if (postError || !post) {
          throw new ApiError(404, "Post was not found.", "target-not-found");
        }
        if (
          profile.role !== "admin" && comment.author_id !== user.id &&
          post.author_id !== user.id
        ) {
          throw new ApiError(
            403,
            "Only a content owner or Admin may clean this Comment.",
            "target-not-owned",
          );
        }
        const { data: rows, error } = await service
          .from("community_attachments")
          .select("id")
          .eq("comment_id", targetId)
          .eq("status", "removed")
          .is("storage_deleted_at", null)
          .limit(200);
        if (error) {
          throw new ApiError(
            503,
            "Comment attachment cleanup state could not be read.",
            "attachment-check-failed",
          );
        }
        candidateIds.push(...(rows ?? []).map((row) => String(row.id)));
      }
      candidates = await cleanupCandidatesForIds(
        service,
        Array.from(new Set(candidateIds)),
      );
    }

    // Atomically win the race against finalization for every uploading row.
    const uploadingIds = candidates
      .filter((row) => row.status === "uploading")
      .map((row) => row.id);
    let newlyRemoved: CommunityAttachmentRow[] = [];
    if (uploadingIds.length > 0) {
      const { data, error } = await service
        .from("community_attachments")
        .update({
          status: "removed",
          removal_reason: "Attachment upload was cancelled",
          removed_at: new Date().toISOString(),
          removed_by: user.id,
        })
        .in("id", uploadingIds)
        .eq("status", "uploading")
        .select(attachmentColumns);
      if (error) {
        throw new ApiError(
          503,
          "Attachment cleanup state could not be saved.",
          "attachment-database-unavailable",
        );
      }
      newlyRemoved = (data ?? []) as unknown as CommunityAttachmentRow[];
    }

    // Already-removed rows are safe to delete.  Uploading rows are included only
    // when the conditional update above actually changed them to removed.
    const removable = [
      ...candidates.filter((row) => row.status === "removed"),
      ...newlyRemoved,
    ];
    const paths = Array.from(new Set(removable.map((row) => row.storage_path)));
    if (paths.length > 0) {
      const { error } = await service.storage
        .from("community-attachments")
        .remove(paths);
      if (error) {
        throw new ApiError(
          503,
          "Hidden attachment bytes could not be cleaned yet. Please retry.",
          "attachment-cleanup-unavailable",
        );
      }

      // Mark successfully cleaned rows so a large target's next 200-row call
      // advances instead of selecting the same retained audit rows forever.
      const { error: markError } = await service
        .from("community_attachments")
        .update({ storage_deleted_at: new Date().toISOString() })
        .in("id", removable.map((row) => row.id))
        .eq("status", "removed");
      if (markError) {
        throw new ApiError(
          503,
          "Attachment cleanup audit could not be saved. Please retry.",
          "attachment-database-unavailable",
        );
      }
    }

    return jsonResponse(request, {
      cleaned: paths.length,
      attachment_ids: removable.map((row) => row.id),
      limited: candidates.length >= 200,
    });
  } catch (error) {
    return errorResponse(request, error, correlationId);
  }
});
