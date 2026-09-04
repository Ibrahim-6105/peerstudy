// One simple gateway for protected PeerStudy backend operations.
//
// Beginner note:
// Screens call clearly named methods here instead of repeating Supabase table,
// Storage, RPC, and Edge Function details throughout the app.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:peerstudy/models/community_attachment.dart';
import 'package:peerstudy/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// BackendException exposes a safe message without leaking server internals.
class BackendException implements Exception {
  // code lets a screen distinguish validation, conflict, and network failures.
  const BackendException(
    this.message, {
    this.code = 'unknown',
    this.currentVersion,
    this.requestId,
    this.httpStatus,
  });

  // This is the reviewed message displayed to the user.
  final String message;

  // This stable short code is useful in tests and retry decisions.
  final String code;

  // A version conflict may return the latest server-owned version.
  final int? currentVersion;

  // Edge Function failures include a safe correlation id for dashboard logs.
  final String? requestId;

  // HTTP status helps tests distinguish connection and server failures.
  final int? httpStatus;

  // Dart prints only the safe message when a widget catches this exception.
  @override
  String toString() => message;
}

// SignedUploadSession is the legacy name for one private material upload.
//
// New sessions use the signed-in Supabase client for the actual Storage write,
// so Storage RLS evaluates the Admin identity at upload time.  The old fields
// remain available because older callers may still inspect them.
class SignedUploadSession {
  // Keep the original constructor shape source-compatible with older callers.
  const SignedUploadSession({
    required this.uploadId,
    required this.uploadUrl,
    required this.requiredHeaders,
    required this.expiresAt,
    this.materialId,
    this.version,
    this.storagePath,
    this.uploadToken,
    this.mimeType = 'application/pdf',
  });

  // For materials, uploadId is the pending subject_materials UUID.
  final String uploadId;

  // This is the authenticated object endpoint for new material sessions.
  final Uri uploadUrl;

  // The official SDK supplies authentication; callers add no custom headers.
  final Map<String, String> requiredHeaders;

  // The app refuses to reuse an obviously expired upload session.
  final DateTime expiresAt;

  // The material UUID is present for official PDF uploads.
  final String? materialId;

  // Legacy screens may still display a replacement version.
  final int? version;

  // Private path inside the subject-materials bucket.
  final String? storagePath;

  // Legacy signed-upload sessions may still contain a one-time token.
  final String? uploadToken;

  // Bucket MIME validation allows only application/pdf for materials.
  final String mimeType;

  // fromMap supports test doubles and older screen contracts.
  factory SignedUploadSession.fromMap(Map<Object?, Object?> data) {
    // Convert optional response headers into a typed immutable map.
    final headers = <String, String>{};
    final rawHeaders = data['requiredHeaders'] ?? data['required_headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        headers[entry.key.toString()] = entry.value.toString();
      }
    }

    // Reject an invalid signed URL before an upload starts.
    final rawUrl = data['uploadUrl'] ?? data['upload_url'];
    final url = Uri.tryParse(rawUrl?.toString() ?? '');
    if (url == null || !url.hasScheme) {
      throw const BackendException(
        'The server returned an invalid upload address.',
        code: 'invalid-response',
      );
    }

    // Build the immutable session using current and legacy field aliases.
    return SignedUploadSession(
      uploadId: (data['uploadId'] ?? data['upload_id'])?.toString() ?? '',
      uploadUrl: url,
      requiredHeaders: Map<String, String>.unmodifiable(headers),
      expiresAt: _dateTimeFromResponse(data['expiresAt'] ?? data['expires_at']),
      materialId: (data['materialId'] ?? data['material_id'])?.toString(),
      version: (data['version'] as num?)?.toInt(),
      storagePath: (data['storagePath'] ?? data['storage_path'])?.toString(),
      uploadToken: (data['uploadToken'] ?? data['upload_token'])?.toString(),
      mimeType:
          (data['mimeType'] ?? data['mime_type'])?.toString() ??
          'application/pdf',
    );
  }
}

// A screen receives progress as sent bytes and total bytes.
typedef SignedUploadProgress = void Function(int sentBytes, int totalBytes);

// UserAccessResult describes one audited Admin account-status change.
class UserAccessResult {
  // The corrected FYP needs status restriction, not arbitrary role promotion.
  const UserAccessResult({
    required this.targetUserId,
    required this.action,
    required this.version,
    required this.role,
    required this.status,
    required this.isBlocked,
    required this.auditId,
    required this.authSessionRevocation,
    required this.requiresOperatorAction,
  });

  // UUID of the affected profile.
  final String targetUserId;

  // Stable action name, normally set-status.
  final String action;

  // Updated concurrency version when supplied by the backend.
  final int version;

  // Role remains student or admin only.
  final String role;

  // Status is active or restricted.
  final String status;

  // Compatibility value: restricted accounts are considered blocked.
  final bool isBlocked;

  // UUID of the audit row when returned.
  final String auditId;

  // Supabase session invalidation is handled by the backend where configured.
  final String authSessionRevocation;

  // True only when a server response explicitly requests operator follow-up.
  final bool requiresOperatorAction;

  // fromMap tolerates a compact PostgreSQL JSON response.
  factory UserAccessResult.fromMap(
    Map<Object?, Object?> data, {
    required String expectedTargetUserId,
    required String expectedAction,
    required int expectedVersion,
  }) {
    // Normalize the corrected two-role and two-status values.
    final role = data['role']?.toString() ?? 'student';
    final status = data['status']?.toString() ?? '';
    if (!const {'student', 'admin'}.contains(role) ||
        !const {'active', 'restricted'}.contains(status)) {
      throw const BackendException(
        'The server returned an invalid account update.',
        code: 'invalid-response',
      );
    }

    // Build a complete result even when optional audit metadata is absent.
    return UserAccessResult(
      targetUserId:
          (data['target_user_id'] ?? data['targetUserId'])?.toString() ??
          expectedTargetUserId,
      action: data['action']?.toString() ?? expectedAction,
      version: (data['version'] as num?)?.toInt() ?? expectedVersion + 1,
      role: role,
      status: status,
      isBlocked:
          (data['is_blocked'] ?? data['isBlocked']) == true ||
          status == 'restricted',
      auditId: (data['audit_id'] ?? data['auditId'])?.toString() ?? '',
      authSessionRevocation:
          (data['auth_session_revocation'] ?? data['authSessionRevocation'])
              ?.toString() ??
          'not-required',
      requiresOperatorAction:
          (data['requires_operator_action'] ??
              data['requiresOperatorAction']) ==
          true,
    );
  }
}

// BackendApiService is the app's only protected backend gateway.
class BackendApiService {
  // Tests may inject a SupabaseClient; production uses the shared initialized one.
  BackendApiService({SupabaseClient? client})
    : _client = client ?? _readyClient();

  // Every request uses the current Supabase Auth access token automatically.
  final SupabaseClient _client;

  // Replacement uploads remember the previous private path until approval.
  final Map<String, String> _replacementOldPaths = <String, String>{};

  // Public signup creates only a Student profile through the database trigger.
  Future<String> registerStudent({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      // Supabase stores the name in metadata for the profile-creation trigger.
      final response = await _client.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: <String, dynamic>{'full_name': fullName.trim()},
      );

      // A session exists when email confirmation is disabled for phone testing.
      return response.session?.accessToken ?? '';
    } on AuthException catch (error) {
      throw BackendException(error.message, code: error.code ?? 'auth-error');
    }
  }

  // Re-read the protected profile before opening a role interface.
  Future<Map<Object?, Object?>> openSession() async {
    // The Auth user UUID is the profiles primary key.
    final user = _requireUser();

    // RLS allows the signed-in account to read its own profile.
    final row = await _client
        .from('profiles')
        .select('id, full_name, role, status, created_at, updated_at')
        .eq('id', user.id)
        .single();

    // Return an immutable object-key map for existing callers.
    return Map<Object?, Object?>.unmodifiable(row);
  }

  // Create short-lived external-viewer access for one approved official PDF.
  //
  // Community attachments already use this reliable signed-URL pattern. Using
  // the same path for lecture PDFs avoids device-specific blank screens from
  // an embedded renderer while Storage RLS still checks the signed-in account
  // before the URL is created.
  Future<Uri> requestMaterialAccess(String materialId) async {
    final cleanMaterialId = _requiredUuidArgument(materialId, 'PDF');
    try {
      // RLS and this explicit filter both require an approved material.
      final row = await _client
          .from('subject_materials')
          .select(
            'id, subject_id, storage_path, version, checksum, status, mime_type, size_bytes',
          )
          .eq('id', cleanMaterialId)
          .eq('status', 'approved')
          .maybeSingle()
          .timeout(const Duration(seconds: 30));

      // A deleted, replaced, unapproved, or RLS-hidden row is an ordinary
      // unavailable state, not an exception that should reach Flutter's UI.
      if (row == null) {
        throw const BackendException(
          'This lecture is no longer available for your account.',
          code: 'not-found',
        );
      }

      // Refuse a non-PDF, foreign path, or incomplete row before signing it.
      final rowId = row['id']?.toString() ?? '';
      final subjectId = row['subject_id']?.toString() ?? '';
      final path = row['storage_path']?.toString() ?? '';
      final checksum = row['checksum']?.toString().toLowerCase() ?? '';
      final mimeType = row['mime_type']?.toString().toLowerCase() ?? '';
      final expectedSize = (row['size_bytes'] as num?)?.toInt() ?? 0;
      if (rowId != cleanMaterialId ||
          !_isOwnedMaterialPath(
            path,
            subjectId: subjectId,
            materialId: cleanMaterialId,
          ) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) ||
          mimeType != 'application/pdf' ||
          expectedSize <= 0 ||
          expectedSize > 25 * 1024 * 1024) {
        throw const BackendException(
          'This material is not available as an approved PDF.',
          code: 'failed-precondition',
        );
      }

      // Ten minutes gives a large lecture enough time to finish browser/PDF-app
      // range requests. The URL is still temporary and contains no permanent
      // public object address. The checksum nonce avoids stale replacement data.
      final signedUrl = await _client.storage
          .from('subject-materials')
          .createSignedUrl(path, 600, cacheNonce: checksum)
          .timeout(const Duration(seconds: 30));

      final uri = Uri.tryParse(signedUrl);
      if (uri == null ||
          !const <String>{'http', 'https'}.contains(uri.scheme) ||
          !uri.hasAuthority) {
        throw const BackendException(
          'The server returned an invalid PDF link. Please retry.',
          code: 'invalid-response',
        );
      }
      return uri;
    } on BackendException {
      rethrow;
    } on TimeoutException {
      throw const BackendException(
        'The secure PDF link took too long. Check your connection and retry.',
        code: 'network-timeout',
      );
    } on StorageException catch (error) {
      final status = int.tryParse(error.statusCode ?? '');
      if (status == 401 || status == 403) {
        throw const BackendException(
          'Your account cannot open this PDF. Sign in again and retry.',
          code: 'permission-denied',
        );
      }
      if (status == 404) {
        throw const BackendException(
          'This PDF file is missing. Ask an Admin to replace it.',
          code: 'not-found',
        );
      }
      throw const BackendException(
        'The PDF could not be opened securely. Check your connection and retry.',
        code: 'storage-error',
      );
    } on PostgrestException catch (error) {
      throw _postgrestBackendException(error);
    } catch (_) {
      throw const BackendException(
        'The PDF could not be opened. Check your connection and retry.',
        code: 'network-error',
      );
    }
  }

  // Create a pending Admin PDF upload or replace one existing material.
  Future<SignedUploadSession> createMaterialUpload({
    required String subjectId,
    required String title,
    required String fileName,
    required int sizeBytes,
    String summary = '',
    String? materialId,
    int? expectedVersion,
  }) async {
    // Validate values before creating a database row or upload session.
    final user = _requireUser();
    final cleanSubjectId = _requiredUuidArgument(subjectId, 'Subject');
    final cleanTitle = _requiredText(title, 'Material title');
    final cleanFileName = _safePdfFileName(fileName);
    final isReplacement = materialId?.trim().isNotEmpty == true;
    if (sizeBytes <= 0 || sizeBytes > 25 * 1024 * 1024) {
      throw const BackendException(
        'Choose a PDF no larger than 25 MB.',
        code: 'invalid-file',
      );
    }
    if (isReplacement && (expectedVersion == null || expectedVersion < 1)) {
      throw const BackendException(
        'Refresh this PDF before replacing it.',
        code: 'invalid-argument',
      );
    }

    // Reuse the existing UUID for replacement or derive a fresh valid UUID.
    final id = isReplacement
        ? _requiredUuidArgument(materialId!, 'PDF')
        : _uuidFromText(
            '${user.id}|$cleanSubjectId|$cleanFileName|${DateTime.now().microsecondsSinceEpoch}',
          );

    // A new unique path prevents a viewer from receiving stale replacement bytes.
    final storagePath =
        '$cleanSubjectId/$id/${DateTime.now().toUtc().millisecondsSinceEpoch}_$cleanFileName';

    // Shared metadata is written before upload with fail-closed uploading status.
    final values = <String, dynamic>{
      'id': id,
      'subject_id': cleanSubjectId,
      'uploaded_by': user.id,
      'title': cleanTitle,
      'summary': summary.trim(),
      'storage_path': storagePath,
      'mime_type': 'application/pdf',
      'size_bytes': sizeBytes,
      'checksum': null,
      'status': 'uploading',
      'approved_by': null,
      'approved_at': null,
    };

    try {
      // A replacement keeps its old private path until the new PDF is approved.
      if (isReplacement) {
        final current = await _client
            .from('subject_materials')
            .select('subject_id, storage_path, version')
            .eq('id', id)
            .maybeSingle();
        if (current == null) {
          throw const BackendException(
            'This PDF no longer exists. Refresh the material list.',
            code: 'not-found',
          );
        }
        if (current['subject_id']?.toString() != cleanSubjectId) {
          throw const BackendException(
            'This PDF does not belong to the selected Subject.',
            code: 'failed-precondition',
          );
        }
        final currentVersion = (current['version'] as num?)?.toInt();
        if (currentVersion != expectedVersion) {
          throw BackendException(
            'This PDF changed on another Admin device. Refresh and try again.',
            code: 'conflict',
            currentVersion: currentVersion,
          );
        }
        final oldPath = current['storage_path']?.toString() ?? '';
        if (oldPath != storagePath &&
            _isOwnedMaterialPath(
              oldPath,
              subjectId: cleanSubjectId,
              materialId: id,
            )) {
          _replacementOldPaths[id] = oldPath;
        }
      }

      // Admin-only RLS protects both the insert and replacement update.
      if (!isReplacement) {
        await _client.from('subject_materials').insert(values);
      } else {
        final updateValues = Map<String, dynamic>.from(values)..remove('id');
        final updated = await _client
            .from('subject_materials')
            .update(updateValues)
            .eq('id', id)
            .eq('version', expectedVersion!)
            .select('id')
            .maybeSingle();
        if (updated == null || updated['id']?.toString() != id) {
          _replacementOldPaths.remove(id);
          throw const BackendException(
            'This PDF changed on another Admin device. Refresh and try again.',
            code: 'conflict',
          );
        }
      }

      // Return the exact authenticated object endpoint.  No bearer-equivalent
      // upload token is minted: uploadMaterialStream performs the write through
      // the signed-in Storage client so the insert policy is checked then.
      return SignedUploadSession(
        uploadId: id,
        uploadUrl: _storageObjectUri(
          storageUrl: _client.storage.url,
          bucket: 'subject-materials',
          path: storagePath,
        ),
        requiredHeaders: const <String, String>{},
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
        materialId: id,
        version: (expectedVersion ?? 0) + 1,
        storagePath: storagePath,
      );
    } on StorageException catch (error) {
      throw BackendException(error.message, code: 'storage-error');
    } on PostgrestException catch (error) {
      throw _postgrestBackendException(error);
    }
  }

  // Publish a material only after uploadMaterialStream saved its checksum.
  Future<Map<Object?, Object?>> finalizeMaterialUpload(String uploadId) async {
    final cleanUploadId = _requiredUuidArgument(uploadId, 'PDF upload');
    try {
      // The approved constraint proves that checksum and approval fields exist.
      final row = await _client
          .from('subject_materials')
          .update(<String, dynamic>{
            'status': 'approved',
            'approved_by': _requireUser().id,
            'approved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', cleanUploadId)
          .eq('status', 'uploading')
          .select()
          .maybeSingle();
      if (row == null) {
        throw const BackendException(
          'This PDF upload is no longer active. Refresh and try again.',
          code: 'conflict',
        );
      }

      // Delete replacement bytes only after the new metadata is approved.
      final oldPath = _replacementOldPaths.remove(cleanUploadId) ?? '';
      final subjectId = row['subject_id']?.toString() ?? '';
      if (_isOwnedMaterialPath(
        oldPath,
        subjectId: subjectId,
        materialId: cleanUploadId,
      )) {
        try {
          await _client.storage.from('subject-materials').remove(<String>[
            oldPath,
          ]);
        } catch (_) {
          // The old object remains private and unreferenced if cleanup retries
          // are needed; the newly approved material stays usable.
        }
      }

      // Return the canonical published row.
      return Map<Object?, Object?>.unmodifiable(row);
    } on PostgrestException catch (error) {
      throw _postgrestBackendException(error);
    }
  }

  // Update only safe material metadata under Admin-only RLS.
  Future<Map<Object?, Object?>> updateMaterialMetadata({
    required String materialId,
    required int expectedVersion,
    required String title,
    required String summary,
  }) async {
    try {
      // PostgreSQL returns the updated row for an honest success message.
      final row = await _client
          .from('subject_materials')
          .update(<String, dynamic>{
            'title': _requiredText(title, 'Material title'),
            'summary': summary.trim(),
          })
          .eq('id', materialId)
          .select()
          .single();
      return Map<Object?, Object?>.unmodifiable(row);
    } on PostgrestException catch (error) {
      throw _postgrestBackendException(error);
    }
  }

  // Permanently delete one official PDF while preserving Quiz/score history.
  //
  // The database prepares a durable job before Storage is touched. If the app
  // closes or the network drops, calling this method again resumes that job.
  Future<Map<Object?, Object?>> deleteMaterialPermanently({
    required String materialId,
    required int expectedVersion,
    required String reason,
  }) async {
    final cleanMaterialId = _requiredUuidArgument(materialId, 'PDF');
    if (expectedVersion < 1) {
      throw const BackendException(
        'A valid PDF and version are required.',
        code: 'invalid-argument',
      );
    }

    // Prepare first: this immediately revokes Student access, retires linked
    // Quizzes, freezes the path, and makes concurrent mutations fail closed.
    final prepared =
        await _rpcMap('admin_prepare_material_deletion', <String, Object?>{
          'p_material_id': cleanMaterialId,
          'p_expected_version': expectedVersion,
          'p_reason': _requiredText(reason, 'Deletion reason'),
        });

    final outcome = _validatedRpcOutcome(
      prepared,
      allowed: const <String>{'prepared', 'completed', 'already_deleted'},
      operation: 'PDF deletion',
    );
    _validateAllRpcIds(prepared, operation: 'PDF deletion');
    _validateRpcId(
      prepared,
      key: 'material_id',
      expected: cleanMaterialId,
      operation: 'PDF deletion',
    );
    final dependencyCounts = _validatedOptionalCountMap(
      prepared,
      key: 'dependency_counts',
      operation: 'PDF deletion',
    );

    if (outcome == 'already_deleted') {
      final paths = _deletionStoragePaths(
        prepared,
        expectedMaterialId: cleanMaterialId,
      );
      if (paths.isNotEmpty) {
        throw const BackendException(
          'The server returned unexpected files for a deleted PDF.',
          code: 'invalid-response',
        );
      }
      _replacementOldPaths.remove(cleanMaterialId);
      return prepared;
    }

    final jobId = _validateRpcId(
      prepared,
      key: 'job_id',
      operation: 'PDF deletion',
    );
    final subjectId = _validateRpcId(
      prepared,
      key: 'subject_id',
      operation: 'PDF deletion',
    );
    final paths = _deletionStoragePaths(
      prepared,
      expectedSubjectId: subjectId,
      expectedMaterialId: cleanMaterialId,
    );
    if (paths.isEmpty ||
        (dependencyCounts != null && dependencyCounts['materials'] != 1)) {
      throw const BackendException(
        'The server returned an inconsistent PDF deletion plan.',
        code: 'invalid-response',
      );
    }

    // This is the workflow's only Storage pass.  A missing object is already
    // the desired state; any other failure leaves the prepared job retryable.
    await _deletePrivateStorageObjects(
      bucket: 'subject-materials',
      paths: paths,
      failureMessage:
          'The PDF is hidden, but its private file could not be deleted. Check your connection and tap Delete again.',
    );

    // A completed job is a lost-response retry.  Its response was validated
    // above and the one idempotent Storage pass has already completed.
    if (outcome == 'completed') {
      _replacementOldPaths.remove(cleanMaterialId);
      return prepared;
    }

    // Finalization verifies Storage is absent, deletes only the Material row,
    // and retires/detaches Quizzes without erasing Student attempt history.
    final result = await _rpcMap(
      'admin_finalize_material_deletion',
      <String, Object?>{'p_job_id': jobId},
    );
    _validateDeletionFinalResult(
      result,
      expectedJobId: jobId,
      targetKey: 'material_id',
      expectedTargetId: cleanMaterialId,
      primaryCountKey: 'deleted_materials',
      operation: 'PDF deletion',
    );
    _replacementOldPaths.remove(cleanMaterialId);
    return result;
  }

  // Permanently delete a Subject and PDFs while preserving Quiz/score history.
  // Community Posts are intentionally protected by the backend and make this
  // operation fail with a safe instruction to set the Subject inactive.
  Future<Map<Object?, Object?>> deleteSubjectPermanently({
    required String subjectId,
    required String reason,
  }) async {
    final cleanSubjectId = _requiredUuidArgument(subjectId, 'Subject');

    final prepared =
        await _rpcMap('admin_prepare_subject_deletion', <String, Object?>{
          'p_subject_id': cleanSubjectId,
          'p_reason': _requiredText(reason, 'Deletion reason'),
        });

    final outcome = _validatedRpcOutcome(
      prepared,
      allowed: const <String>{'prepared', 'completed', 'already_deleted'},
      operation: 'Subject deletion',
    );
    _validateAllRpcIds(prepared, operation: 'Subject deletion');
    _validateRpcId(
      prepared,
      key: 'subject_id',
      expected: cleanSubjectId,
      operation: 'Subject deletion',
    );
    final dependencyCounts = _validatedOptionalCountMap(
      prepared,
      key: 'dependency_counts',
      operation: 'Subject deletion',
    );
    final paths = _deletionStoragePaths(
      prepared,
      expectedSubjectId: cleanSubjectId,
    );

    if (outcome == 'already_deleted') {
      if (paths.isNotEmpty) {
        throw const BackendException(
          'The server returned unexpected files for a deleted Subject.',
          code: 'invalid-response',
        );
      }
      return prepared;
    }

    final jobId = _validateRpcId(
      prepared,
      key: 'job_id',
      operation: 'Subject deletion',
    );
    final materialCount = dependencyCounts?['materials'];
    if (dependencyCounts != null &&
        (materialCount == null ||
            paths.length < materialCount ||
            ((materialCount == 0) != paths.isEmpty))) {
      throw const BackendException(
        'The server returned an inconsistent Subject deletion plan.',
        code: 'invalid-response',
      );
    }

    // Delete every snapshotted object once before database finalization.
    await _deletePrivateStorageObjects(
      bucket: 'subject-materials',
      paths: paths,
      failureMessage:
          'The Subject is hidden, but one or more private PDFs could not be deleted. Check your connection and tap Delete again.',
    );

    if (outcome == 'completed') {
      final deletedPaths = paths.toSet();
      _replacementOldPaths.removeWhere(
        (_, path) => deletedPaths.contains(path),
      );
      return prepared;
    }

    final result = await _rpcMap(
      'admin_finalize_subject_deletion',
      <String, Object?>{'p_job_id': jobId},
    );
    _validateDeletionFinalResult(
      result,
      expectedJobId: jobId,
      targetKey: 'subject_id',
      expectedTargetId: cleanSubjectId,
      primaryCountKey: 'deleted_subjects',
      operation: 'Subject deletion',
    );

    // Forget replacement cleanup hints that belonged to the deleted paths.
    final deletedPaths = paths.toSet();
    _replacementOldPaths.removeWhere((_, path) => deletedPaths.contains(path));
    return result;
  }

  // Hide one material while preserving its database, Quiz, and attempt rows.
  //
  // This retains the original archive contract for callers that do not want a
  // hard delete.  Private bytes are cleaned up best-effort after access has
  // already been revoked by the status update.
  Future<Map<Object?, Object?>> archiveMaterial({
    required String materialId,
    required int expectedVersion,
    required String reason,
  }) async {
    final cleanMaterialId = _requiredUuidArgument(materialId, 'PDF');
    final cleanReason = _requiredText(reason, 'Removal reason');
    if (expectedVersion < 1) {
      throw const BackendException(
        'A valid PDF version is required.',
        code: 'invalid-argument',
      );
    }

    try {
      final current = await _client
          .from('subject_materials')
          .select()
          .eq('id', cleanMaterialId)
          .maybeSingle();
      if (current == null) {
        throw const BackendException(
          'This PDF no longer exists. Refresh the material list.',
          code: 'not-found',
        );
      }

      final currentVersion = (current['version'] as num?)?.toInt();
      if (currentVersion != expectedVersion) {
        throw BackendException(
          'This PDF changed on another Admin device. Refresh and try again.',
          code: 'conflict',
          currentVersion: currentVersion,
        );
      }

      Map<String, dynamic> archived = Map<String, dynamic>.from(current);
      if (current['status']?.toString() != 'removed') {
        final updated = await _client
            .from('subject_materials')
            .update(<String, dynamic>{
              'status': 'removed',
              'removal_reason': cleanReason,
              'removed_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', cleanMaterialId)
            .eq('version', expectedVersion)
            .select()
            .maybeSingle();
        if (updated == null) {
          throw const BackendException(
            'This PDF changed on another Admin device. Refresh and try again.',
            code: 'conflict',
          );
        }
        archived = Map<String, dynamic>.from(updated);
      }

      final subjectId = archived['subject_id']?.toString() ?? '';
      final paths = <String>{};
      final currentPath = archived['storage_path']?.toString() ?? '';
      if (_isOwnedMaterialPath(
        currentPath,
        subjectId: subjectId,
        materialId: cleanMaterialId,
      )) {
        paths.add(currentPath);
      }
      final oldPath = _replacementOldPaths.remove(cleanMaterialId) ?? '';
      if (_isOwnedMaterialPath(
        oldPath,
        subjectId: subjectId,
        materialId: cleanMaterialId,
      )) {
        paths.add(oldPath);
      }
      for (final path in paths) {
        try {
          await _client.storage.from('subject-materials').remove(<String>[
            path,
          ]);
        } catch (_) {
          // Archiving remains successful: the object is private and its row is
          // no longer readable by Students. A later cleanup can safely retry.
        }
      }

      return Map<Object?, Object?>.unmodifiable(archived);
    } on PostgrestException catch (error) {
      throw _postgrestBackendException(error);
    }
  }

  // Create one Student text post through the protected PostgreSQL RPC.
  Future<String> createPost({
    required String subjectId,
    required String body,
    required String idempotencyKey,
  }) async {
    // RPC ownership, active status, Subject existence, and length checks are atomic.
    final data = await _rpcMap('create_community_post', <String, Object?>{
      'p_subject_id': subjectId,
      'p_body': body.trim(),
      'p_idempotency_key': _uuidFromText(idempotencyKey),
    });

    // Accept either a JSON object or scalar UUID wrapped by _rpcMap.
    return _responseId(data, const <String>['post_id', 'id', 'value']);
  }

  // Edit the current Student's own post at one exact version.
  Future<Map<Object?, Object?>> editPost({
    required String subjectId,
    required String postId,
    required int expectedVersion,
    required String body,
  }) async {
    final cleanSubjectId = _requiredUuidArgument(subjectId, 'Subject');
    final cleanPostId = _requiredUuidArgument(postId, 'post');
    final cleanBody = _requiredText(body, 'Post');
    if (expectedVersion < 1) {
      throw const BackendException(
        'Reopen Edit before saving this post.',
        code: 'invalid-argument',
      );
    }
    if (cleanBody.runes.length > 5000) {
      throw const BackendException(
        'A post can contain at most 5000 characters.',
        code: 'invalid-argument',
      );
    }

    try {
      // PostgreSQL verifies ownership and rejects a stale version atomically.
      final result = await _rpcMap('update_community_post', <String, Object?>{
        'p_post_id': cleanPostId,
        'p_expected_version': expectedVersion,
        'p_body': cleanBody,
      });
      _validateCommunityEditResult(
        result,
        targetName: 'post',
        idKey: 'id',
        expectedId: cleanPostId,
        parentKey: 'community_id',
        expectedParentId: cleanSubjectId,
        expectedBody: cleanBody,
        expectedVersion: expectedVersion + 1,
      );
      return result;
    } on BackendException catch (error) {
      throw _communityEditException(error, targetName: 'post');
    }
  }

  // Soft-delete the current Student's own post.
  Future<Map<Object?, Object?>> deletePost({
    required String subjectId,
    required String postId,
    required int expectedVersion,
    String reason = 'Removed by owner',
  }) async {
    // The database preserves report references and increments the version.
    final result = await _rpcMap('delete_community_post', <String, Object?>{
      'p_post_id': postId,
      'p_expected_version': expectedVersion,
      'p_reason': reason.trim(),
    });
    // The protected cleanup removes this Post's and its Comments' hidden bytes.
    await _bestEffortCommunityAttachmentCleanup(
      targetType: 'post',
      targetId: postId,
    );
    return result;
  }

  // Add one Student comment with a canonical PostgreSQL timestamp.
  Future<String> addComment({
    required String subjectId,
    required String postId,
    required String body,
    required String idempotencyKey,
  }) async {
    // The Subject parameter prevents attaching a comment across Communities.
    final data = await _rpcMap('create_community_comment', <String, Object?>{
      'p_subject_id': subjectId,
      'p_post_id': postId,
      'p_body': body.trim(),
      'p_idempotency_key': _uuidFromText(idempotencyKey),
    });
    return _responseId(data, const <String>['comment_id', 'id', 'value']);
  }

  // Edit the signed-in Student's own comment at one exact version.
  Future<Map<Object?, Object?>> editComment({
    required String postId,
    required String commentId,
    required int expectedVersion,
    required String body,
  }) async {
    final cleanPostId = _requiredUuidArgument(postId, 'post');
    final cleanCommentId = _requiredUuidArgument(commentId, 'comment');
    final cleanBody = _requiredText(body, 'Comment');
    if (expectedVersion < 1) {
      throw const BackendException(
        'Reopen Edit before saving this comment.',
        code: 'invalid-argument',
      );
    }
    if (cleanBody.runes.length > 2000) {
      throw const BackendException(
        'A comment can contain at most 2000 characters.',
        code: 'invalid-argument',
      );
    }

    try {
      // The RPC performs ownership, active-account, and concurrency checks.
      final result =
          await _rpcMap('update_community_comment', <String, Object?>{
            'p_comment_id': cleanCommentId,
            'p_expected_version': expectedVersion,
            'p_body': cleanBody,
          });
      _validateCommunityEditResult(
        result,
        targetName: 'comment',
        idKey: 'id',
        expectedId: cleanCommentId,
        parentKey: 'post_id',
        expectedParentId: cleanPostId,
        expectedBody: cleanBody,
        expectedVersion: expectedVersion + 1,
      );

      return result;
    } on BackendException catch (error) {
      throw _communityEditException(error, targetName: 'comment');
    }
  }

  // Soft-delete one owned comment while retaining audit history.
  Future<Map<Object?, Object?>> deleteComment({
    required String subjectId,
    required String postId,
    required String commentId,
    required int expectedVersion,
    String reason = 'Removed by owner',
  }) async {
    // The server refuses another student's comment or a stale version.
    final result = await _rpcMap('delete_community_comment', <String, Object?>{
      'p_comment_id': commentId,
      'p_expected_version': expectedVersion,
      'p_reason': reason.trim(),
    });
    // The protected cleanup deletes bytes hidden by the Comment status trigger.
    await _bestEffortCommunityAttachmentCleanup(
      targetType: 'comment',
      targetId: commentId,
    );
    return result;
  }

  // Reserve, upload, and publish one private Community attachment.
  Future<CommunityAttachment> uploadCommunityAttachment({
    required String subjectId,
    required String targetType,
    required String targetId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    required String idempotencyKey,
    SignedUploadProgress? onProgress,
  }) async {
    // Validate locally before creating an uploading database row.
    _requireUser();
    final validationMessage = validateCommunityAttachment(
      fileName: fileName,
      sizeBytes: bytes.length,
    );
    if (validationMessage != null) {
      throw BackendException(validationMessage, code: 'invalid-file');
    }

    // The MIME value must match the reviewed extension instead of caller text.
    final expectedMimeType = communityAttachmentMimeTypeForFileName(fileName);
    if (expectedMimeType == null || expectedMimeType != mimeType) {
      throw const BackendException(
        'The attachment type does not match its file name.',
        code: 'invalid-file',
      );
    }

    // The database contract accepts only a post or a comment target.
    if (!const <String>{'post', 'comment'}.contains(targetType)) {
      throw const BackendException(
        'Choose a post or comment for this attachment.',
        code: 'invalid-argument',
      );
    }

    // Clear this Student's previously removed or expired private bytes before
    // applying the server quota to a new reservation. Network failure is safe:
    // the authoritative reserve call still enforces every limit.
    await _bestEffortCommunityAttachmentCleanup(ownRemoved: true);

    // Reserve metadata first; the server creates the private path itself.
    final reservedMap =
        await _rpcMap('reserve_community_attachment', <String, Object?>{
          'p_subject_id': subjectId.trim(),
          'p_target_type': targetType,
          'p_target_id': targetId.trim(),
          'p_file_name': fileName.trim(),
          'p_mime_type': mimeType,
          'p_size_bytes': bytes.length,
          'p_idempotency_key': _uuidFromText(idempotencyKey),
        });
    final reserved = CommunityAttachment.fromSupabaseRow(
      _stringKeyedMap(reservedMap),
    );
    if (reserved.id.isEmpty || reserved.storagePath.isEmpty) {
      throw const BackendException(
        'The server could not reserve this attachment.',
        code: 'invalid-response',
      );
    }

    // An idempotent retry may receive an attachment already finalized earlier.
    if (reserved.isReady) {
      onProgress?.call(bytes.length, bytes.length);
      return reserved;
    }
    if (reserved.status != 'uploading') {
      // Expired reservations may still own a private object or quota entry.
      // Cleanup is safe because the server has already made the row unreadable.
      await _bestEffortCommunityAttachmentCleanup(attachmentId: reserved.id);
      throw const BackendException(
        'This attachment request was closed. Remove the selection and choose the file again.',
        code: 'attachment-closed',
      );
    }

    // A retry may arrive after Storage accepted all bytes but its response was
    // lost. Finalizing first recovers that upload without overwriting anything.
    try {
      return await finalizeCommunityAttachment(reserved.id);
    } on BackendException catch (error) {
      // Only a definite missing object means the phone should send bytes now.
      if (error.code != 'attachment-object-missing') rethrow;
    }

    try {
      // The SDK sends bytes only to the authenticated private bucket path.
      onProgress?.call(0, bytes.length);
      await _client.storage
          .from('community-attachments')
          .uploadBinary(
            reserved.storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              cacheControl: '0',
              upsert: false,
            ),
          );
      onProgress?.call(bytes.length, bytes.length);
    } on StorageException {
      // Keep the uploading row and stable key so an ambiguous result can retry.
      throw const BackendException(
        'The attachment upload was interrupted. Check your connection and retry the same file.',
        code: 'upload-retryable',
      );
    } on Object {
      // Unknown transport failures are also retryable and never overwrite bytes.
      throw const BackendException(
        'The attachment upload could not be confirmed. Retry the same file.',
        code: 'network-error',
      );
    }

    // Verify magic bytes and checksum only after Storage accepted the upload.
    return finalizeCommunityAttachment(reserved.id);
  }

  // Verify real attachment bytes server-side and return the canonical ready row.
  Future<CommunityAttachment> finalizeCommunityAttachment(
    String attachmentId,
  ) async {
    final cleanAttachmentId = attachmentId.trim();
    try {
      // The authenticated function downloads the private object, checks its
      // magic bytes and checksum, and only then changes status to ready.
      final response = await _client.functions.invoke(
        'finalize-community-attachment',
        body: <String, Object?>{'attachment_id': cleanAttachmentId},
      );
      if (response.status < 200 || response.status >= 300) {
        final errorMap = _normalizeMapResponse(response.data);
        final message =
            errorMap['message']?.toString() ??
            errorMap['error']?.toString() ??
            'The attachment could not be verified.';
        final code = errorMap['code']?.toString().trim() ?? '';
        final requestId = errorMap['request_id']?.toString().trim() ?? '';
        throw BackendException(
          message,
          code: code.isEmpty ? 'attachment-verification' : code,
          requestId: requestId.isEmpty ? null : requestId,
          httpStatus: response.status,
        );
      }

      // Accept either a direct row or {attachment: row} for simple deployment.
      final responseMap = _normalizeMapResponse(response.data);
      final nestedAttachment = responseMap['attachment'];
      final rowMap = nestedAttachment is Map
          ? Map<Object?, Object?>.from(nestedAttachment)
          : responseMap;
      final attachment = CommunityAttachment.fromSupabaseRow(
        _stringKeyedMap(rowMap),
      );
      if (attachment.id != cleanAttachmentId || !attachment.isReady) {
        throw const BackendException(
          'The server did not confirm the verified attachment.',
          code: 'invalid-response',
        );
      }
      return attachment;
    } on FunctionException catch (error) {
      throw _attachmentBackendExceptionFromFunction(error);
    } on BackendException {
      rethrow;
    } on Object {
      throw const BackendException(
        'The attachment verification service is temporarily unavailable. Retry the same file.',
        code: 'network-error',
      );
    }
  }

  // Delete inaccessible Storage bytes after metadata or a parent is removed.
  Future<Map<Object?, Object?>> cleanupCommunityAttachments({
    String? attachmentId,
    String? targetType,
    String? targetId,
    bool ownRemoved = false,
  }) async {
    // Callers choose one attachment, one complete parent, or their own stale
    // reservations. The Edge Function repeats this selector validation.
    final hasAttachment = attachmentId?.trim().isNotEmpty == true;
    final hasTarget =
        targetId?.trim().isNotEmpty == true &&
        const <String>{'post', 'comment'}.contains(targetType?.trim());
    final selectorCount =
        (hasAttachment ? 1 : 0) + (hasTarget ? 1 : 0) + (ownRemoved ? 1 : 0);
    if (selectorCount != 1) {
      throw const BackendException(
        'Choose one attachment cleanup type.',
        code: 'invalid-argument',
      );
    }

    final body = <String, Object?>{};
    if (hasAttachment) {
      body['attachment_id'] = attachmentId!.trim();
    } else if (hasTarget) {
      body['target_type'] = targetType!.trim();
      body['target_id'] = targetId!.trim();
    } else {
      body['own_removed'] = true;
    }

    try {
      // The service-role function can delete every already-hidden child object.
      final response = await _client.functions.invoke(
        'cleanup-community-attachments',
        body: body,
      );
      if (response.status < 200 || response.status >= 300) {
        final errorMap = _normalizeMapResponse(response.data);
        final message =
            errorMap['message']?.toString() ??
            errorMap['error']?.toString() ??
            'Attachment cleanup could not be confirmed.';
        throw BackendException(
          message,
          code: errorMap['code']?.toString() ?? 'attachment-cleanup',
          httpStatus: response.status,
        );
      }
      return _normalizeMapResponse(response.data);
    } on FunctionException catch (error) {
      throw _attachmentBackendExceptionFromFunction(error);
    } on BackendException {
      rethrow;
    } on Object {
      throw const BackendException(
        'Attachment cleanup could not be confirmed.',
        code: 'network-error',
      );
    }
  }

  // Cleanup failure never reverses the authoritative hidden-content status.
  Future<void> _bestEffortCommunityAttachmentCleanup({
    String? attachmentId,
    String? targetType,
    String? targetId,
    bool ownRemoved = false,
  }) async {
    try {
      // One server call is intentionally capped. Continue through later audit
      // rows when an unusually large removed thread reports another page.
      for (var page = 0; page < 10; page += 1) {
        final result = await cleanupCommunityAttachments(
          attachmentId: attachmentId,
          targetType: targetType,
          targetId: targetId,
          ownRemoved: ownRemoved,
        );
        if (result['limited'] != true) return;
      }
    } on Object {
      // A later authorized cleanup call can retry inaccessible private objects.
    }
  }

  // Create a short-lived URL only after the user taps a ready attachment.
  Future<Uri> requestCommunityAttachmentAccess(
    String attachmentId, {
    bool download = false,
  }) async {
    try {
      // RLS verifies that this signed-in account may read the target Community.
      final row = await _client
          .from('community_attachments')
          .select('id, file_name, storage_path, status')
          .eq('id', attachmentId.trim())
          .eq('status', 'ready')
          .single();
      final path = row['storage_path']?.toString() ?? '';
      final fileName = row['file_name']?.toString().trim() ?? '';
      if (path.isEmpty || fileName.isEmpty) {
        throw const BackendException(
          'This attachment is no longer available.',
          code: 'not-found',
        );
      }

      // One minute limits reuse if moderation removes the target after this tap.
      final signedUrl = await _client.storage
          .from('community-attachments')
          .createSignedUrl(
            path,
            60,
            download: download ? DownloadBehavior.named(fileName) : null,
          );
      final uri = Uri.tryParse(signedUrl);
      if (uri == null || !uri.hasScheme) {
        throw const BackendException(
          'The server returned an invalid attachment link.',
          code: 'invalid-response',
        );
      }
      return uri;
    } on BackendException {
      rethrow;
    } on StorageException {
      throw const BackendException(
        'The attachment could not be opened securely. Please retry.',
        code: 'storage-error',
      );
    } on PostgrestException catch (error) {
      throw _postgrestBackendException(error);
    }
  }

  // Hide an owned attachment and then best-effort delete its private bytes.
  Future<void> removeCommunityAttachment(
    CommunityAttachment attachment, {
    String reason = 'Removed by owner',
  }) async {
    // The RPC checks ownership and changes status before bytes are removed.
    await _rpcMap('remove_community_attachment', <String, Object?>{
      'p_attachment_id': attachment.id,
      'p_reason': reason.trim(),
    });

    // Prefer protected service cleanup because it remains safe across roles.
    try {
      await cleanupCommunityAttachments(attachmentId: attachment.id);
      return;
    } on Object {
      // A normal active owner may still clean the exact removed path directly.
    }

    // A cleanup failure cannot make the now-hidden attachment readable.
    try {
      await _client.storage.from('community-attachments').remove(<String>[
        attachment.storagePath,
      ]);
    } on Object {
      // Network, SDK, and Storage failures never reverse the hidden metadata.
      // A later server cleanup can safely remove this private orphan.
    }
  }

  // Return only the signed-in Student's bounded scored quiz history.
  Future<List<Map<Object?, Object?>>> getRecentQuizActivity({
    String? subjectId,
    int limit = 5,
  }) async {
    try {
      // Snapshot identity keeps history discoverable after a live Subject FK is
      // detached during permanent catalog deletion.
      final userId = _requireUser().id;
      final rawSubjectId = subjectId?.trim() ?? '';
      final cleanSubjectId = rawSubjectId.isEmpty
          ? ''
          : _requiredUuidArgument(rawSubjectId, 'Subject');
      dynamic rows;
      try {
        var query = _client
            .from('quiz_attempts')
            .select(
              'id, quiz_id, subject_id, subject_id_snapshot, score, total, completed_at',
            )
            .eq('student_id', userId);
        if (cleanSubjectId.isNotEmpty) {
          query = query.eq('subject_id_snapshot', cleanSubjectId);
        }
        rows = await query
            .order('completed_at', ascending: false)
            .limit(limit.clamp(1, 20));
      } on PostgrestException catch (error) {
        // During a rolling deployment, an older backend may not have the new
        // snapshot column yet. Fall back only for that exact schema mismatch.
        final missingSnapshot =
            error.code == '42703' ||
            error.message.toLowerCase().contains('subject_id_snapshot');
        if (!missingSnapshot) rethrow;

        var legacyQuery = _client
            .from('quiz_attempts')
            .select('id, quiz_id, subject_id, score, total, completed_at')
            .eq('student_id', userId);
        if (cleanSubjectId.isNotEmpty) {
          legacyQuery = legacyQuery.eq('subject_id', cleanSubjectId);
        }
        rows = await legacyQuery
            .order('completed_at', ascending: false)
            .limit(limit.clamp(1, 20));
      }

      // Map snake_case backend fields into the existing activity UI contract.
      if (rows is! List) {
        throw const BackendException(
          'The server returned invalid quiz history.',
          code: 'invalid-response',
        );
      }
      return rows
          .map<Map<Object?, Object?>>((rawRow) {
            if (rawRow is! Map) {
              throw const BackendException(
                'The server returned invalid quiz history.',
                code: 'invalid-response',
              );
            }
            final row = rawRow;
            return <Object?, Object?>{
              'attemptId': row['id']?.toString() ?? '',
              'subjectId':
                  row['subject_id_snapshot']?.toString() ??
                  row['subject_id']?.toString() ??
                  '',
              'score': row['score'],
              'total': row['total'],
              'submittedAt': row['completed_at']?.toString() ?? '',
            };
          })
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw _postgrestBackendException(error);
    }
  }

  // Generate exactly ten questions from one selected approved material.
  Future<Map<Object?, Object?>> generateQuiz(
    String subjectId, {
    required String materialId,
    required String idempotencyKey,
  }) {
    // The Edge Function keeps the AI key and correct answers off the phone.
    return _invokeEdgeMap('generate-quiz', <String, Object?>{
      'subject_id': subjectId,
      'material_id': materialId,
      'idempotency_key': _uuidFromText(idempotencyKey),
    });
  }

  // Submit exactly ten selected answers for trusted server scoring.
  Future<Map<Object?, Object?>> submitQuiz({
    required String quizId,
    required List<int> answers,
    required String idempotencyKey,
  }) {
    // The Edge Function returns score and corrections only after submission.
    return _invokeEdgeMap('submit-quiz', <String, Object?>{
      'quiz_id': quizId,
      'answers': answers,
      'idempotency_key': _uuidFromText(idempotencyKey),
    });
  }

  // Create a private report that targets exactly one post or comment.
  Future<String> reportContent({
    required String subjectId,
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
    String? parentId,
  }) async {
    // Reporter identity comes from auth.uid() inside PostgreSQL.
    final params = <String, Object?>{
      'p_subject_id': subjectId,
      'p_target_type': targetType,
      'p_target_id': targetId,
      'p_reason': reason,
      'p_details': details.trim(),
    };
    if (parentId != null && parentId.trim().isNotEmpty) {
      params['p_parent_id'] = parentId.trim();
    }
    final data = await _rpcMap('create_content_report', params);
    return _responseId(data, const <String>['report_id', 'id', 'value']);
  }

  // Resolve one report with the exact corrected Admin actions.
  Future<Map<Object?, Object?>> moderateReport({
    required String reportId,
    required String action,
    required int expectedReportVersion,
    required int expectedTargetVersion,
    required String resolutionNote,
    String blockReason = '',
  }) async {
    // Normalize old screen values while the new Admin UI uses exact names.
    final correctedAction = switch (action) {
      'dismiss' => 'dismiss',
      'remove' || 'remove-content' => 'remove',
      'restrict' || 'remove-and-block' => 'restrict',
      _ => action,
    };
    final result = await _rpcMap('admin_resolve_report', <String, Object?>{
      'p_report_id': reportId,
      'p_action': correctedAction,
      'p_resolution_note': resolutionNote.trim(),
    });
    if (correctedAction == 'remove') {
      final targetType = result['target_type']?.toString() ?? '';
      final targetId = result['target_id']?.toString() ?? '';
      if (targetId.isNotEmpty &&
          const <String>{'post', 'comment'}.contains(targetType)) {
        await _bestEffortCommunityAttachmentCleanup(
          targetType: targetType,
          targetId: targetId,
        );
      }
    }
    return result;
  }

  // Activate or restrict one Student account through the audited Admin RPC.
  Future<UserAccessResult> setUserStatus({
    required String targetUserId,
    required int expectedVersion,
    required String status,
    required String reason,
  }) async {
    // Only the corrected active and restricted states are accepted.
    if (!const <String>{'active', 'restricted'}.contains(status)) {
      throw const BackendException(
        'Choose active or restricted status.',
        code: 'invalid-argument',
      );
    }

    // The RPC writes both the profile state and immutable audit record.
    final data = await _rpcMap('admin_set_user_status', <String, Object?>{
      'p_profile_id': targetUserId,
      'p_status': status,
      'p_reason': reason.trim(),
    });
    return UserAccessResult.fromMap(
      data,
      expectedTargetUserId: targetUserId,
      expectedAction: 'set-status',
      expectedVersion: expectedVersion,
    );
  }

  // Old unblock maps to the corrected active status.
  Future<UserAccessResult> unblockUser({
    required String targetUserId,
    required int expectedVersion,
    required String reason,
  }) {
    return setUserStatus(
      targetUserId: targetUserId,
      expectedVersion: expectedVersion,
      status: 'active',
      reason: reason,
    );
  }

  // Upload material bytes with the current Supabase session attached.
  //
  // Unlike an upload token, this request reaches Storage as the signed-in
  // Admin, so the subject-materials INSERT policy is evaluated at write time.
  Future<void> uploadMaterialStream({
    required SignedUploadSession session,
    required Stream<List<int>> bytes,
    required int sizeBytes,
    SignedUploadProgress? onProgress,
  }) async {
    // Refuse an expired, incomplete, or incorrectly scoped material session.
    _requireUser();
    final path = session.storagePath;
    if (sizeBytes <= 0 ||
        sizeBytes > 25 * 1024 * 1024 ||
        session.expiresAt.isBefore(DateTime.now()) ||
        path == null ||
        !_isSafeStoragePath(path)) {
      throw const BackendException(
        'The upload session is invalid or expired. Select the PDF again.',
        code: 'failed-precondition',
      );
    }
    final pathSegments = path.split('/');
    final materialId = session.materialId ?? session.uploadId;
    if (pathSegments.length != 3 ||
        !_isUuid(pathSegments[0]) ||
        pathSegments[1] != materialId ||
        !_isUuid(materialId) ||
        !pathSegments.last.toLowerCase().endsWith('.pdf') ||
        session.mimeType != 'application/pdf') {
      throw const BackendException(
        'The upload session does not match this PDF.',
        code: 'failed-precondition',
      );
    }

    // Collect at most the validated 25 MB PDF into one SDK-compatible buffer.
    final builder = BytesBuilder(copy: false);
    var sentBytes = 0;
    try {
      await for (final chunk in bytes.timeout(const Duration(seconds: 30))) {
        sentBytes += chunk.length;
        if (sentBytes > sizeBytes || sentBytes > 25 * 1024 * 1024) {
          throw const BackendException(
            'The selected PDF is larger than the validated size.',
            code: 'invalid-file',
          );
        }
        builder.add(chunk);
        onProgress?.call(sentBytes, sizeBytes);
      }

      // Exact byte length detects incomplete file-picker streams.
      if (sentBytes != sizeBytes) {
        throw const BackendException(
          'The selected PDF could not be read completely.',
          code: 'invalid-file',
        );
      }

      // The normal authenticated upload includes the current access token.
      // Storage RLS therefore re-checks the uploading row and Admin identity.
      final data = builder.takeBytes();
      if (!_hasPdfSignature(data)) {
        throw const BackendException(
          'The selected file is not a readable PDF.',
          code: 'invalid-file',
        );
      }
      await _client.storage
          .from('subject-materials')
          .uploadBinary(
            path,
            data,
            fileOptions: FileOptions(
              contentType: session.mimeType,
              upsert: false,
            ),
          );

      // Save a deterministic checksum before the approved constraint is applied.
      final checksum = sha256.convert(data).toString();
      final updated = await _client
          .from('subject_materials')
          .update(<String, dynamic>{
            'checksum': checksum,
            'size_bytes': data.length,
          })
          .eq('id', materialId)
          .eq('storage_path', path)
          .eq('status', 'uploading')
          .select('id')
          .maybeSingle();
      if (updated == null || updated['id']?.toString() != materialId) {
        throw const BackendException(
          'This PDF upload is no longer active. Refresh and try again.',
          code: 'conflict',
        );
      }
    } on BackendException {
      rethrow;
    } on StorageException catch (error) {
      final status = int.tryParse(error.statusCode ?? '');
      if (status == 401 || status == 403) {
        throw const BackendException(
          'Your Admin session cannot upload this PDF. Sign in again or refresh.',
          code: 'permission-denied',
        );
      }
      throw const BackendException(
        'The secure PDF upload failed. Check your connection and try again.',
        code: 'upload-failed',
      );
    } on PostgrestException catch (error) {
      throw _postgrestBackendException(error);
    } catch (_) {
      throw const BackendException(
        'The secure upload did not finish. No material was published.',
        code: 'upload-failed',
      );
    }
  }

  // Keep the original method name working while callers migrate to the name
  // that accurately describes the authenticated upload.
  @Deprecated('Use uploadMaterialStream instead.')
  Future<void> uploadSignedStream({
    required SignedUploadSession session,
    required Stream<List<int>> bytes,
    required int sizeBytes,
    SignedUploadProgress? onProgress,
  }) {
    return uploadMaterialStream(
      session: session,
      bytes: bytes,
      sizeBytes: sizeBytes,
      onProgress: onProgress,
    );
  }

  // Call a PostgreSQL function and normalize its JSON/scalar response to a map.
  Future<Map<Object?, Object?>> _rpcMap(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
    try {
      // Supabase automatically adds the current access token to the RPC request.
      final data = await _client.rpc(functionName, params: parameters);
      return _normalizeMapResponse(data);
    } on PostgrestException catch (error) {
      throw _postgrestBackendException(error);
    } catch (error) {
      if (error is BackendException) rethrow;
      throw const BackendException(
        'PeerStudy could not confirm the database response. Check your connection and retry.',
        code: 'network-error',
      );
    }
  }

  // Invoke an authenticated Supabase Edge Function and normalize its response.
  Future<Map<Object?, Object?>> _invokeEdgeMap(
    String functionName,
    Map<String, Object?> body,
  ) async {
    try {
      // Edge Functions receive the current Student JWT automatically.
      final response = await _client.functions.invoke(functionName, body: body);

      // A non-success HTTP code must never be treated as a saved quiz.
      if (response.status < 200 || response.status >= 300) {
        final errorMap = _normalizeMapResponse(response.data);
        final message =
            errorMap['message']?.toString() ??
            errorMap['error']?.toString() ??
            'The quiz service rejected the request.';
        throw BackendException(message, code: 'function-error');
      }

      // Return the exact JSON object produced by the function.
      return _normalizeMapResponse(response.data);
    } on FunctionException catch (error) {
      // The SDK throws before returning non-success FunctionResponse objects.
      // Read its structured details instead of showing its noisy toString().
      throw backendExceptionFromFunction(error);
    } on BackendException {
      rethrow;
    } catch (_) {
      throw const BackendException(
        'The AI quiz service is temporarily unavailable. Check your connection and retry.',
        code: 'network-error',
      );
    }
  }

  // Delete bounded batches through the official Storage API.  A thrown error
  // leaves the durable database job prepared, so the same Admin action retries
  // safely instead of pretending the PDF was fully removed.
  Future<void> _deletePrivateStorageObjects({
    required String bucket,
    required List<String> paths,
    required String failureMessage,
  }) async {
    const batchSize = 100;
    try {
      for (var start = 0; start < paths.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, paths.length);
        try {
          await _client.storage.from(bucket).remove(paths.sublist(start, end));
        } on StorageException catch (error) {
          // DELETE is idempotent. A 404 means every requested object in this
          // batch is already absent, which is the required final state.
          if (_isMissingStorageObject(error)) continue;
          throw BackendException(
            failureMessage,
            code: 'storage-delete-failed',
            httpStatus: int.tryParse(error.statusCode ?? ''),
          );
        }
      }
    } on BackendException {
      rethrow;
    } catch (_) {
      throw BackendException(failureMessage, code: 'network-error');
    }
  }

  // Require the currently authenticated Supabase identity.
  User _requireUser() {
    // Protected calls fail clearly after sign-out or session expiry.
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const BackendException(
        'Sign in before using this feature.',
        code: 'unauthenticated',
      );
    }
    return user;
  }
}

// Convert a Supabase FunctionException into one short, safe app error.
//
// This helper is public only so a small unit test can verify every error shape.
// Screens should continue calling BackendApiService methods normally.
BackendException backendExceptionFromFunction(FunctionException error) {
  // Status zero means DNS, connectivity, or transport failed before a response.
  if (error.status == 0) {
    return const BackendException(
      'The AI quiz service could not be reached. Check your connection and retry.',
      code: 'network-error',
      httpStatus: 0,
    );
  }

  // JSON responses normally arrive as a Map, while proxies may return JSON text.
  Map<Object?, Object?> details = const <Object?, Object?>{};
  if (error.details is Map) {
    details = Map<Object?, Object?>.from(error.details as Map);
  } else if (error.details is String) {
    try {
      final decoded = jsonDecode(error.details as String);
      if (decoded is Map) details = Map<Object?, Object?>.from(decoded);
    } catch (_) {
      // Raw HTML/text is never shown because it is not a reviewed app message.
    }
  }

  // The Edge Functions use error, code, and request_id for safe failures.
  final serverMessage =
      details['message']?.toString().trim() ??
      details['error']?.toString().trim() ??
      '';
  final serverCode = details['code']?.toString().trim() ?? '';
  final requestId = details['request_id']?.toString().trim() ?? '';

  // Reject empty or unexpectedly long provider/proxy strings at the UI boundary.
  final message = serverMessage.isNotEmpty && serverMessage.length <= 300
      ? serverMessage
      : switch (error.status) {
          401 => 'Sign in again before generating a quiz.',
          429 => 'The AI quiz limit is busy. Wait a moment and retry.',
          _ => 'The AI quiz service is temporarily unavailable. Please retry.',
        };

  return BackendException(
    message,
    code: serverCode.isEmpty ? 'function-error' : serverCode,
    requestId: requestId.isEmpty ? null : requestId,
    httpStatus: error.status,
  );
}

// Reuse structured Edge Function parsing with attachment-specific fallbacks.
BackendException _attachmentBackendExceptionFromFunction(
  FunctionException error,
) {
  final parsed = backendExceptionFromFunction(error);
  final message = switch (parsed.message) {
    'The AI quiz service could not be reached. Check your connection and retry.' =>
      'The attachment verification service could not be reached. Check your connection and retry.',
    'Sign in again before generating a quiz.' =>
      'Sign in again before uploading an attachment.',
    'The AI quiz limit is busy. Wait a moment and retry.' =>
      'The attachment service is busy. Wait a moment and retry.',
    'The AI quiz service is temporarily unavailable. Please retry.' =>
      'The attachment verification service is temporarily unavailable. Please retry.',
    _ => parsed.message,
  };
  return BackendException(
    message,
    code: parsed.code,
    currentVersion: parsed.currentVersion,
    requestId: parsed.requestId,
    httpStatus: parsed.httpStatus,
  );
}

// Resolve the shared client only after successful startup configuration.
SupabaseClient _readyClient() {
  // A configuration failure should not silently connect to a demo backend.
  if (!SupabaseService.isReady) {
    throw StateError('Supabase is not ready. Restart PeerStudy.');
  }
  return SupabaseService.client;
}

// Normalize JSON maps, one-row lists, scalar UUIDs, and empty RPC responses.
Map<Object?, Object?> _normalizeMapResponse(dynamic data) {
  // PostgreSQL JSON objects arrive as Map<String, dynamic>.
  if (data is Map) return Map<Object?, Object?>.unmodifiable(data);

  // A SETOF function may wrap one object inside a list.
  if (data is List && data.length == 1 && data.first is Map) {
    return Map<Object?, Object?>.unmodifiable(data.first as Map);
  }

  // UUID-returning RPCs use a scalar value.
  if (data is String || data is num || data is bool) {
    return Map<Object?, Object?>.unmodifiable(<Object?, Object?>{
      'value': data,
    });
  }

  // Void functions return null after a successful atomic mutation.
  if (data == null || (data is List && data.isEmpty)) {
    return const <Object?, Object?>{};
  }

  // Any other shape is a backend contract error.
  throw const BackendException(
    'The server returned an invalid response.',
    code: 'invalid-response',
  );
}

// Validate the private object paths returned by a catalog-deletion RPC.
List<String> _deletionStoragePaths(
  Map<Object?, Object?> response, {
  String? expectedSubjectId,
  String? expectedMaterialId,
}) {
  final rawPaths = response['storage_paths'];
  if (rawPaths is! List) {
    throw const BackendException(
      'The server returned invalid PDF deletion paths.',
      code: 'invalid-response',
    );
  }

  final paths = <String>[];
  final seen = <String>{};
  for (final value in rawPaths) {
    if (value is! String || !_isSafeStoragePath(value)) {
      throw const BackendException(
        'The server returned an unsafe PDF deletion path.',
        code: 'invalid-response',
      );
    }
    final segments = value.split('/');
    final belongsToSubject =
        expectedSubjectId == null ||
        (segments.length >= 3 && segments.first == expectedSubjectId);
    final belongsToMaterial =
        expectedMaterialId == null ||
        (segments.length >= 3 && segments[1] == expectedMaterialId);
    if (!belongsToSubject || !belongsToMaterial || !seen.add(value)) {
      throw const BackendException(
        'The server returned a PDF path outside the deletion target.',
        code: 'invalid-response',
      );
    }
    paths.add(value);
  }
  return List<String>.unmodifiable(paths);
}

// Accept only the path grammar produced by createMaterialUpload.
bool _isSafeStoragePath(String path) {
  if (path.isEmpty ||
      path.length > 1000 ||
      path != path.trim() ||
      path.startsWith('/') ||
      path.endsWith('/') ||
      path.contains('..') ||
      path.contains('\\')) {
    return false;
  }

  final safeSegment = RegExp(r'^[A-Za-z0-9._-]+$');
  final segments = path.split('/');
  if (segments.length != 3 ||
      !_isUuid(segments[0]) ||
      !_isUuid(segments[1]) ||
      !segments[2].toLowerCase().endsWith('.pdf') ||
      segments.any(
        (segment) =>
            segment.isEmpty ||
            segment == '.' ||
            segment == '..' ||
            !safeSegment.hasMatch(segment),
      )) {
    return false;
  }
  return true;
}

bool _isOwnedMaterialPath(
  String path, {
  required String subjectId,
  required String materialId,
}) {
  if (!_isSafeStoragePath(path)) return false;
  final segments = path.split('/');
  return segments[0] == subjectId && segments[1] == materialId;
}

// Validate an RPC outcome instead of treating an unknown server state as done.
String _validatedRpcOutcome(
  Map<Object?, Object?> response, {
  required Set<String> allowed,
  required String operation,
}) {
  final raw = response['outcome'];
  final outcome = raw is String ? raw.trim() : '';
  if (outcome.isEmpty || outcome != raw || !allowed.contains(outcome)) {
    throw BackendException(
      'The server returned an invalid $operation outcome.',
      code: 'invalid-response',
    );
  }
  return outcome;
}

// Require a canonical UUID and optionally bind it to the requested target.
String _validateRpcId(
  Map<Object?, Object?> response, {
  required String key,
  required String operation,
  String? expected,
}) {
  final raw = response[key];
  final id = raw is String ? raw : '';
  if (!_isUuid(id) || (expected != null && id != expected)) {
    throw BackendException(
      'The server returned an invalid $operation identifier.',
      code: 'invalid-response',
    );
  }
  return id;
}

// Every returned dependency count must be a real non-negative integer.
Map<String, int>? _validatedOptionalCountMap(
  Map<Object?, Object?> response, {
  required String key,
  required String operation,
}) {
  final raw = response[key];
  if (raw == null) return null;
  if (raw is! Map) {
    throw BackendException(
      'The server returned invalid $operation counts.',
      code: 'invalid-response',
    );
  }

  final counts = <String, int>{};
  for (final entry in raw.entries) {
    final name = entry.key;
    final count = _nonnegativeInteger(entry.value);
    if (name is! String || name.trim().isEmpty || count == null) {
      throw BackendException(
        'The server returned invalid $operation counts.',
        code: 'invalid-response',
      );
    }
    counts[name] = count;
  }
  return Map<String, int>.unmodifiable(counts);
}

// Validate the finalizer contract before announcing an irreversible success.
void _validateDeletionFinalResult(
  Map<Object?, Object?> response, {
  required String expectedJobId,
  required String targetKey,
  required String expectedTargetId,
  required String primaryCountKey,
  required String operation,
}) {
  final outcome = _validatedRpcOutcome(
    response,
    allowed: const <String>{'deleted', 'already_deleted'},
    operation: operation,
  );
  _validateAllRpcIds(response, operation: operation);
  _validateRpcId(
    response,
    key: 'job_id',
    expected: expectedJobId,
    operation: operation,
  );
  _validateRpcId(
    response,
    key: targetKey,
    expected: expectedTargetId,
    operation: operation,
  );

  for (final entry in response.entries) {
    final key = entry.key;
    if (key is String &&
        (key.startsWith('deleted_') ||
            key.startsWith('retired_') ||
            key.startsWith('preserved_') ||
            key.endsWith('_count')) &&
        _nonnegativeInteger(entry.value) == null) {
      throw BackendException(
        'The server returned invalid $operation counts.',
        code: 'invalid-response',
      );
    }
  }

  // A server running an obsolete destructive finalizer must never be reported
  // as the history-preserving success promised by the Admin confirmation.
  for (final key in const <String>{
    'deleted_quizzes',
    'deleted_quiz_attempts',
    'deleted_attempts',
    'deleted_scores',
  }) {
    final count = _nonnegativeInteger(response[key]);
    if (response.containsKey(key) && count != 0) {
      throw BackendException(
        'The server did not preserve Quiz and score history during $operation.',
        code: 'invalid-response',
      );
    }
  }

  final primaryCount = _nonnegativeInteger(response[primaryCountKey]);
  if ((outcome == 'deleted' && primaryCount != 1) ||
      (outcome == 'already_deleted' &&
          response.containsKey(primaryCountKey) &&
          primaryCount != 0)) {
    throw BackendException(
      'The server did not confirm the completed $operation.',
      code: 'invalid-response',
    );
  }
}

void _validateAllRpcIds(
  Map<Object?, Object?> response, {
  required String operation,
}) {
  for (final entry in response.entries) {
    final key = entry.key;
    if (key is String &&
        key.endsWith('_id') &&
        (entry.value is! String || !_isUuid(entry.value as String))) {
      throw BackendException(
        'The server returned an invalid $operation identifier.',
        code: 'invalid-response',
      );
    }
  }
}

int? _nonnegativeInteger(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value != value.round()) {
    return null;
  }
  return value.toInt();
}

bool _isMissingStorageObject(StorageException error) {
  if (error.statusCode == '404') return true;
  final details = '${error.error ?? ''} ${error.message}'.toLowerCase();
  return details.contains('object not found') ||
      details.contains('not_found') ||
      details.contains('no such object');
}

// PDF permits a small binary preamble, so inspect its first 1024 bytes rather
// than assuming the signature is at byte zero.
bool _hasPdfSignature(Uint8List bytes) {
  if (bytes.length < 5) return false;
  final headerLength = bytes.length < 1024 ? bytes.length : 1024;
  return latin1
      .decode(bytes.sublist(0, headerLength), allowInvalid: true)
      .contains('%PDF-');
}

// Convert an object-keyed RPC response into a normal string-keyed model map.
Map<String, dynamic> _stringKeyedMap(Map<Object?, Object?> data) {
  return <String, dynamic>{
    for (final entry in data.entries) entry.key.toString(): entry.value,
  };
}

// Find a UUID in a normalized RPC response.
String _responseId(Map<Object?, Object?> data, List<String> keys) {
  // Try the small known result field names in order.
  for (final key in keys) {
    final value = data[key]?.toString() ?? '';
    if (value.isNotEmpty) return value;
  }

  // Missing IDs make a create result ambiguous and therefore unsafe.
  throw const BackendException(
    'The server did not confirm the new record.',
    code: 'invalid-response',
  );
}

// Convert PostgREST errors into stable application errors.
BackendException _postgrestBackendException(PostgrestException error) {
  // PostgreSQL insufficient_privilege is shown as a simple permission failure.
  if (error.code == '42501') {
    return const BackendException(
      'You do not have permission to perform this action.',
      code: 'permission-denied',
    );
  }

  // Unique violations commonly indicate an exact idempotent retry.
  if (error.code == '23505') {
    return const BackendException(
      'This request was already completed. Refresh to see the saved result.',
      code: 'already-exists',
    );
  }

  // Raise-exception RPC validation uses the reviewed database message.
  return BackendException(error.message, code: error.code ?? 'database-error');
}

// Give Community edit failures one stable, actionable message instead of a
// raw PostgreSQL exception. The editor remains open so network errors can retry.
BackendException _communityEditException(
  BackendException error, {
  required String targetName,
}) {
  return switch (error.code) {
    '40001' => BackendException(
      'This $targetName changed on another device. '
      'Close and reopen Edit to review the latest version.',
      code: 'version-conflict',
    ),
    'P0002' => BackendException(
      'This $targetName no longer exists. Close the editor to refresh.',
      code: 'not-found',
    ),
    '55000' => BackendException(
      'This $targetName was removed and can no longer be edited.',
      code: 'removed',
    ),
    _ => error,
  };
}

// Verify that an edit RPC confirmed the exact row and next version requested.
// A malformed or outdated backend response is never announced as a success.
void _validateCommunityEditResult(
  Map<Object?, Object?> result, {
  required String targetName,
  required String idKey,
  required String expectedId,
  required String parentKey,
  required String expectedParentId,
  required String expectedBody,
  required int expectedVersion,
}) {
  final version = result['version'];
  final valid =
      result[idKey]?.toString() == expectedId &&
      result[parentKey]?.toString() == expectedParentId &&
      result['body']?.toString() == expectedBody &&
      version is num &&
      version.isFinite &&
      version == expectedVersion &&
      result['status']?.toString() == 'active' &&
      result['is_removed'] == false;
  if (!valid) {
    throw BackendException(
      'The server could not confirm the edited $targetName. Refresh and retry.',
      code: 'invalid-response',
    );
  }
}

// Validate and trim required user text.
String _requiredText(String value, String label) {
  // Empty values never reach the network.
  final clean = value.trim();
  if (clean.isEmpty) {
    throw BackendException('$label cannot be empty.', code: 'invalid-argument');
  }
  return clean;
}

// Convert an arbitrary stable request string into a deterministic UUID.
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

bool _isUuid(String value) => _uuidPattern.hasMatch(value);

String _requiredUuidArgument(String value, String label) {
  final clean = value.trim().toLowerCase();
  if (!_isUuid(clean)) {
    throw BackendException('Choose a valid $label.', code: 'invalid-argument');
  }
  return clean;
}

String _uuidFromText(String value) {
  // Preserve an already valid UUID so callers can inspect database idempotency.
  final clean = value.trim().toLowerCase();
  if (_isUuid(clean)) return clean;

  // SHA-256 makes exact retries produce the exact same 128-bit identifier.
  final bytes = sha256.convert(utf8.encode(value)).bytes.take(16).toList();

  // Mark the derived identifier as RFC 4122 version 5 and variant 1.
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  // Convert the sixteen bytes into canonical hyphenated UUID text.
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}

// Build a displayable authenticated endpoint without exposing an access token.
Uri _storageObjectUri({
  required String storageUrl,
  required String bucket,
  required String path,
}) {
  final root = Uri.tryParse(storageUrl);
  if (root == null || !root.hasScheme || root.host.isEmpty) {
    throw const BackendException(
      'The Storage service is not configured correctly.',
      code: 'failed-precondition',
    );
  }
  final base = storageUrl.endsWith('/')
      ? storageUrl.substring(0, storageUrl.length - 1)
      : storageUrl;
  final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
  return Uri.parse('$base/object/${Uri.encodeComponent(bucket)}/$encodedPath');
}

// Keep only a safe PDF file name for private Storage paths.
String _safePdfFileName(String value) {
  // Remove directories and replace unsupported characters with underscores.
  final fileName = value.replaceAll('\\', '/').split('/').last.trim();
  final sanitized = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  // The Admin material tool accepts PDFs only.
  if (!sanitized.toLowerCase().endsWith('.pdf')) {
    throw const BackendException(
      'Choose a valid PDF file.',
      code: 'invalid-file',
    );
  }

  // Keep the extension while normalizing repeated dots rejected by the
  // subject_materials storage_path database constraint.
  final stem = sanitized
      .substring(0, sanitized.length - 4)
      .replaceAll(RegExp(r'[.]{2,}'), '_');
  if (stem.isEmpty || stem == '.') {
    throw const BackendException(
      'Choose a valid PDF file.',
      code: 'invalid-file',
    );
  }
  final safe = '$stem.pdf';
  return safe;
}

// Parse ISO-8601, DateTime, or millisecond expiry values.
DateTime _dateTimeFromResponse(Object? value) {
  // Tests may pass DateTime directly.
  if (value is DateTime) return value;

  // Supabase JSON timestamps are ISO-8601 strings.
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }

  // Legacy responses may contain Unix milliseconds.
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }

  // Missing expiry means the signed operation is unsafe to use.
  throw const BackendException(
    'The server returned an invalid expiry time.',
    code: 'invalid-response',
  );
}
