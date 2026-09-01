// Simple Community attachment values shared by the feed, uploader, and tests.
//
// Beginner note:
// The real file bytes stay only in CommunityAttachmentDraft while uploading.
// CommunityAttachment stores safe database metadata and never stores a public URL.

import 'dart:typed_data';

// One post or comment may contain at most three active attachments.
const int communityAttachmentMaxCount = 3;

// Each attachment may contain at most ten mebibytes of data.
const int communityAttachmentMaxBytes = 10 * 1024 * 1024;

// The picker uses this short extension list to hide unsupported file types.
const List<String> communityAttachmentAllowedExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
  'pdf',
  'txt',
];

// The backend accepts these exact MIME values.
const Map<String, String> _communityMimeTypeByExtension = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
};

// CommunityAttachment describes one ready private file returned by Supabase.
class CommunityAttachment {
  // All fields are immutable so a feed refresh creates predictable UI values.
  const CommunityAttachment({
    required this.id,
    required this.uploadedBy,
    required this.fileName,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.status,
    required this.createdAt,
    this.postId,
    this.commentId,
  });

  // UUID of the attachment metadata row.
  final String id;

  // Exactly one of postId or commentId is set by the database.
  final String? postId;
  final String? commentId;

  // Auth UUID of the student who uploaded the file.
  final String uploadedBy;

  // Safe display name kept for the attachment card.
  final String fileName;

  // Private Storage path; the UI never displays this value.
  final String storagePath;

  // Server-validated MIME type used for the file icon.
  final String mimeType;

  // Exact uploaded byte count used for a friendly size label.
  final int sizeBytes;

  // Only ready rows are shown, but retaining status makes parsing defensive.
  final String status;

  // Canonical database creation time.
  final DateTime createdAt;

  // A ready attachment is allowed to request a temporary signed URL.
  bool get isReady => status == 'ready';

  // Convert metadata to the same snake_case shape returned by PostgREST.
  Map<String, dynamic> toSupabaseRow() {
    return <String, dynamic>{
      'post_id': postId,
      'comment_id': commentId,
      'uploaded_by': uploadedBy,
      'file_name': fileName,
      'storage_path': storagePath,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'status': status,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  // Build safe typed metadata from one Supabase row.
  factory CommunityAttachment.fromSupabaseRow(
    Map<String, dynamic> data, {
    String? id,
  }) {
    return CommunityAttachment(
      id: id ?? data['id']?.toString() ?? '',
      postId: _nullableAttachmentText(data['post_id']),
      commentId: _nullableAttachmentText(data['comment_id']),
      uploadedBy: data['uploaded_by']?.toString() ?? '',
      fileName: data['file_name']?.toString() ?? 'Attachment',
      storagePath: data['storage_path']?.toString() ?? '',
      mimeType: data['mime_type']?.toString() ?? 'application/octet-stream',
      sizeBytes: (data['size_bytes'] as num?)?.toInt() ?? 0,
      status: data['status']?.toString() ?? 'uploading',
      createdAt:
          DateTime.tryParse(data['created_at']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

// CommunityAttachmentDraft holds one validated local selection until upload.
class CommunityAttachmentDraft {
  // The UI creates this object only after validateCommunityAttachment succeeds.
  const CommunityAttachmentDraft({
    required this.idempotencyKey,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  // One stable UUID is reused if an ambiguous network response needs a retry.
  final String idempotencyKey;

  // Original safe basename shown to the student.
  final String fileName;

  // MIME type derived from the reviewed extension list.
  final String mimeType;

  // In-memory bytes supplied to the private Supabase bucket.
  final Uint8List bytes;

  // The byte list is the authoritative size used by the backend reservation.
  int get sizeBytes => bytes.length;
}

// Return the approved MIME type for a file name, or null when unsupported.
String? communityAttachmentMimeTypeForFileName(String fileName) {
  final cleanName = fileName.trim().toLowerCase();
  final lastDot = cleanName.lastIndexOf('.');
  if (lastDot <= 0 || lastDot == cleanName.length - 1) return null;
  return _communityMimeTypeByExtension[cleanName.substring(lastDot + 1)];
}

// Validate a selected file before any network request begins.
String? validateCommunityAttachment({
  required String fileName,
  required int sizeBytes,
}) {
  final cleanName = fileName.trim();
  if (cleanName.isEmpty) return 'The selected file has no name.';
  if (cleanName.length > 180 ||
      cleanName.contains('/') ||
      cleanName.contains('\\') ||
      cleanName.contains('\u0000')) {
    return 'Choose a file with a shorter, simple name.';
  }
  if (communityAttachmentMimeTypeForFileName(fileName) == null) {
    return 'Choose a JPG, PNG, WebP, PDF, or TXT file.';
  }
  if (sizeBytes <= 0) return 'The selected file is empty.';
  if (sizeBytes > communityAttachmentMaxBytes) {
    return 'Each attachment must be 10 MB or smaller.';
  }
  return null;
}

// Format bytes without adding a large formatting dependency.
String formatCommunityAttachmentSize(int sizeBytes) {
  if (sizeBytes < 1024) return '$sizeBytes B';
  final kibibytes = sizeBytes / 1024;
  if (kibibytes < 1024) return '${kibibytes.toStringAsFixed(1)} KB';
  final mebibytes = kibibytes / 1024;
  return '${mebibytes.toStringAsFixed(1)} MB';
}

// Turn a nullable database value into either useful text or null.
String? _nullableAttachmentText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
