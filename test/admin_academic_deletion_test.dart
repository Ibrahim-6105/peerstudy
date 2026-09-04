// Fast regression contracts for permanent Admin Subject/PDF deletion.
//
// These source-level checks complement the HTTP workflow tests. The migration
// is also applied to a PostgreSQL-compatible test engine during development so
// its trigger and foreign-key behavior can be exercised with real rows.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migrationPath =
      'supabase/migrations/20260904000100_admin_permanent_catalog_deletion.sql';

  test('deletion is prepare, Storage proof, then bounded hard delete', () {
    final migration = File(migrationPath);
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync().toLowerCase();

    expect(
      sql,
      contains('create table if not exists public.admin_catalog_deletion_jobs'),
    );
    expect(sql, contains('public.admin_prepare_material_deletion'));
    expect(sql, contains('public.admin_finalize_material_deletion'));
    expect(sql, contains('public.admin_prepare_subject_deletion'));
    expect(sql, contains('public.admin_finalize_subject_deletion'));

    final materialFinalizer = _section(
      sql,
      'create or replace function public.admin_finalize_material_deletion',
      'create or replace function public.admin_prepare_subject_deletion',
    );
    final materialStorageProof = materialFinalizer.indexOf(
      "o.bucket_id = 'subject-materials'",
    );
    final materialHardDelete = materialFinalizer.indexOf(
      'delete from public.subject_materials',
    );
    expect(materialStorageProof, greaterThanOrEqualTo(0));
    expect(materialHardDelete, greaterThan(materialStorageProof));
    expect(materialFinalizer, isNot(contains('delete from public.quizzes')));
    expect(
      materialFinalizer,
      isNot(contains('delete from public.quiz_attempts')),
    );

    final subjectFinalizer = _section(
      sql,
      'create or replace function public.admin_finalize_subject_deletion',
      'drop policy if exists subjects_admin_delete',
    );
    final subjectStorageProof = subjectFinalizer.indexOf(
      "o.bucket_id = 'subject-materials'",
    );
    final materialsDelete = subjectFinalizer.indexOf(
      'delete from public.subject_materials',
    );
    final subjectDelete = subjectFinalizer.indexOf(
      'delete from public.subjects',
    );
    expect(subjectStorageProof, greaterThanOrEqualTo(0));
    expect(materialsDelete, greaterThan(subjectStorageProof));
    expect(subjectDelete, greaterThan(materialsDelete));
    expect(subjectFinalizer, isNot(contains('delete from public.quizzes')));
    expect(
      subjectFinalizer,
      isNot(contains('delete from public.quiz_attempts')),
    );
  });

  test('quiz and Student attempt history survives catalog deletion', () {
    final sql = File(migrationPath).readAsStringSync().toLowerCase();

    for (final column in <String>[
      'subject_id_snapshot',
      'material_id_snapshot',
      'subject_name_snapshot',
      'material_title_snapshot',
      'material_checksum_snapshot',
    ]) {
      expect(sql, contains(column));
    }
    expect(
      sql,
      contains(
        'alter table public.quiz_attempts\n  add column if not exists subject_id_snapshot',
      ),
    );
    expect(
      RegExp(r'on delete set null').allMatches(sql).length,
      greaterThanOrEqualTo(3),
    );
    expect(sql, contains("status = 'retired'"));
    expect(sql, contains('public.enforce_quiz_catalog_context'));
    expect(sql, contains('public.enforce_attempt_subject'));
    expect(sql, contains("'preserved_attempts'"));

    final materialPrepare = _section(
      sql,
      'create or replace function public.admin_prepare_material_deletion',
      'create or replace function public.admin_finalize_material_deletion',
    );
    final subjectPrepare = _section(
      sql,
      'create or replace function public.admin_prepare_subject_deletion',
      'create or replace function public.admin_finalize_subject_deletion',
    );
    expect(materialPrepare, contains('update public.quizzes'));
    expect(materialPrepare, contains("status = 'retired'"));
    expect(subjectPrepare, contains('update public.quizzes'));
    expect(subjectPrepare, contains("status = 'retired'"));
  });

  test('writer locks, path ledger, and restrictive FKs close deletion races', () {
    final sql = File(migrationPath).readAsStringSync().toLowerCase();

    // Both foreign-key layers protect Student posts from accidental cascades.
    expect(
      sql,
      contains('drop constraint if exists communities_subject_id_fkey'),
    );
    expect(
      sql,
      contains('drop constraint if exists community_posts_community_id_fkey'),
    );
    expect(
      RegExp(
        r'foreign key \([^)]*\)[\s\S]{0,120}on delete restrict',
      ).allMatches(sql).length,
      greaterThanOrEqualTo(2),
    );
    expect(
      sql,
      contains(
        'this subject contains community posts. set it to inactive instead of deleting student content.',
      ),
    );

    // Every replacement path remains discoverable until permanent cleanup.
    expect(sql, contains('material_storage_objects'));
    expect(sql, contains('storage_path'));
    expect(sql, contains('for key share'));
    expect(sql, contains('for update'));

    // Upload RLS re-checks the exact uploading row while the deletion workflow
    // owns row locks, and raw catalog deletes are no longer client-accessible.
    expect(sql, contains('public.can_upload_subject_material_object(name)'));
    expect(sql, contains('public.can_delete_subject_material_object(name)'));
    expect(sql, contains('drop policy if exists subjects_admin_delete'));
    expect(
      sql,
      contains('drop policy if exists subject_materials_admin_delete'),
    );
    expect(
      sql,
      contains(
        'revoke delete on table public.subjects, public.subject_materials',
      ),
    );
  });

  test('Flutter and Edge functions use the safe permanent-delete contract', () {
    final service = File(
      'lib/services/backend_api_service.dart',
    ).readAsStringSync();
    final dashboard = File(
      'lib/screens/admin/admin_dashboard_screen.dart',
    ).readAsStringSync();
    final generateQuiz = File(
      'supabase/functions/generate-quiz/index.ts',
    ).readAsStringSync();
    final submitQuiz = File(
      'supabase/functions/submit-quiz/index.ts',
    ).readAsStringSync();

    final createUpload = _section(
      service,
      'Future<SignedUploadSession> createMaterialUpload',
      'Future<Map<Object?, Object?>> finalizeMaterialUpload',
    );
    final authenticatedUpload = _section(
      service,
      'Future<void> uploadMaterialStream',
      '@Deprecated(\'Use uploadMaterialStream instead.\')',
    );
    expect(createUpload, isNot(contains('createSignedUploadUrl')));
    expect(authenticatedUpload, contains('.uploadBinary('));
    expect(authenticatedUpload, isNot(contains('uploadBinaryToSignedUrl')));

    final materialDelete = _section(
      service,
      'deleteMaterialPermanently({',
      'deleteSubjectPermanently({',
    );
    final subjectDelete = _section(
      service,
      'deleteSubjectPermanently({',
      'Future<Map<Object?, Object?>> archiveMaterial',
    );
    expect(
      RegExp(
        r'_deletePrivateStorageObjects\(',
      ).allMatches(materialDelete).length,
      1,
    );
    expect(
      RegExp(
        r'_deletePrivateStorageObjects\(',
      ).allMatches(subjectDelete).length,
      1,
    );
    expect(materialDelete, contains('_validateDeletionFinalResult('));
    expect(subjectDelete, contains('_validateDeletionFinalResult('));
    expect(service, contains("'subject_id_snapshot'"));
    expect(service, contains("'deleted_quiz_attempts'"));

    expect(dashboard, contains('_backend.deleteSubjectPermanently('));
    expect(dashboard, contains('_backend.deleteMaterialPermanently('));
    expect(dashboard, contains('Delete PDF permanently'));
    expect(dashboard, contains('score/attempt history are preserved'));
    expect(dashboard, isNot(contains('_backend.archiveMaterial(')));

    expect(
      generateQuiz,
      contains(
        'select("id, subject_id, material_id, title, questions, status")',
      ),
    );
    expect(generateQuiz, contains('existing.status !== "ready"'));
    expect(generateQuiz, contains('raced.status !== "ready"'));
    expect(submitQuiz, contains('typeof quiz.subject_id !== "string"'));
    expect(submitQuiz, contains('typeof quiz.material_id !== "string"'));
  });
}

String _section(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  if (start < 0) {
    throw StateError('Missing section start: $startMarker');
  }
  final end = source.indexOf(endMarker, start + startMarker.length);
  if (end < 0) {
    throw StateError('Missing section end: $endMarker');
  }
  return source.substring(start, end);
}
