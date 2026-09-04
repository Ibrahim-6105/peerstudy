import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peerstudy/services/backend_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const baseUrl = 'https://peerstudy.test';
  const apiKey = 'test-publishable-key';
  const materialId = '11111111-1111-4111-8111-111111111111';
  const subjectId = '22222222-2222-4222-8222-222222222222';
  const jobId = '33333333-3333-4333-8333-333333333333';
  const storagePath = '$subjectId/$materialId/notes.pdf';

  test(
    'permanent material deletion prepares, removes bytes, then finalizes',
    () async {
      final calls = <String>[];
      final client = SupabaseClient(
        baseUrl,
        apiKey,
        httpClient: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');

          if (request.url.path.endsWith('/admin_prepare_material_deletion')) {
            final body = jsonDecode(request.body) as Map;
            expect(body['p_material_id'], materialId);
            expect(body['p_expected_version'], 4);
            return _jsonResponse(<String, Object?>{
              'outcome': 'prepared',
              'job_id': jobId,
              'material_id': materialId,
              'subject_id': subjectId,
              'storage_paths': <String>[storagePath],
            }, request: request);
          }

          if (request.url.path == '/storage/v1/object/subject-materials') {
            final body = jsonDecode(request.body) as Map;
            expect(body['prefixes'], <String>[storagePath]);
            return _jsonResponse(const <Object?>[], request: request);
          }

          if (request.url.path.endsWith('/admin_finalize_material_deletion')) {
            final body = jsonDecode(request.body) as Map;
            expect(body['p_job_id'], jobId);
            return _jsonResponse(<String, Object?>{
              'outcome': 'deleted',
              'job_id': jobId,
              'material_id': materialId,
              'deleted_materials': 1,
            }, request: request);
          }

          return _jsonResponse(
            <String, Object?>{'message': 'Unexpected test request'},
            request: request,
            statusCode: 500,
          );
        }),
      );
      addTearDown(client.dispose);

      final result = await BackendApiService(client: client)
          .deleteMaterialPermanently(
            materialId: materialId,
            expectedVersion: 4,
            reason: 'Permanent Admin deletion',
          );

      expect(result['outcome'], 'deleted');
      expect(calls, <String>[
        'POST /rest/v1/rpc/admin_prepare_material_deletion',
        'DELETE /storage/v1/object/subject-materials',
        'POST /rest/v1/rpc/admin_finalize_material_deletion',
      ]);
    },
  );

  test(
    'Storage failure leaves the prepared job retryable and skips finalize',
    () async {
      final calls = <String>[];
      final client = SupabaseClient(
        baseUrl,
        apiKey,
        httpClient: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/admin_prepare_material_deletion')) {
            return _jsonResponse(<String, Object?>{
              'outcome': 'prepared',
              'job_id': jobId,
              'material_id': materialId,
              'subject_id': subjectId,
              'storage_paths': <String>[storagePath],
            }, request: request);
          }
          if (request.url.path == '/storage/v1/object/subject-materials') {
            return _jsonResponse(
              <String, Object?>{'message': 'temporary storage failure'},
              request: request,
              statusCode: 503,
            );
          }
          return _jsonResponse(const <String, Object?>{}, request: request);
        }),
      );
      addTearDown(client.dispose);

      await expectLater(
        BackendApiService(client: client).deleteMaterialPermanently(
          materialId: materialId,
          expectedVersion: 4,
          reason: 'Permanent Admin deletion',
        ),
        throwsA(
          isA<BackendException>()
              .having((error) => error.code, 'code', 'storage-delete-failed')
              .having((error) => error.message, 'message', contains('hidden')),
        ),
      );

      expect(calls, <String>[
        'POST /rest/v1/rpc/admin_prepare_material_deletion',
        'DELETE /storage/v1/object/subject-materials',
      ]);
    },
  );

  test(
    'already-deleted Subject is an idempotent success without Storage calls',
    () async {
      final calls = <String>[];
      final client = SupabaseClient(
        baseUrl,
        apiKey,
        httpClient: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          return _jsonResponse(<String, Object?>{
            'outcome': 'already_deleted',
            'subject_id': subjectId,
            'storage_paths': const <String>[],
          }, request: request);
        }),
      );
      addTearDown(client.dispose);

      final result = await BackendApiService(client: client)
          .deleteSubjectPermanently(
            subjectId: subjectId,
            reason: 'Permanent Admin deletion',
          );

      expect(result['outcome'], 'already_deleted');
      expect(calls, <String>[
        'POST /rest/v1/rpc/admin_prepare_subject_deletion',
      ]);
    },
  );

  test('empty Subject deletes without making a Storage request', () async {
    final calls = <String>[];
    final client = SupabaseClient(
      baseUrl,
      apiKey,
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/admin_prepare_subject_deletion')) {
          return _jsonResponse(<String, Object?>{
            'outcome': 'prepared',
            'job_id': jobId,
            'subject_id': subjectId,
            'storage_paths': const <String>[],
            'dependency_counts': const <String, int>{'materials': 0},
          }, request: request);
        }
        if (request.url.path.endsWith('/admin_finalize_subject_deletion')) {
          return _jsonResponse(<String, Object?>{
            'outcome': 'deleted',
            'job_id': jobId,
            'subject_id': subjectId,
            'deleted_subjects': 1,
            'deleted_materials': 0,
            'retired_quizzes': 0,
            'preserved_attempts': 0,
          }, request: request);
        }
        return _jsonResponse(
          <String, Object?>{'message': 'Unexpected test request'},
          request: request,
          statusCode: 500,
        );
      }),
    );
    addTearDown(client.dispose);

    final result = await BackendApiService(client: client)
        .deleteSubjectPermanently(
          subjectId: subjectId,
          reason: 'Permanent Admin deletion',
        );

    expect(result['outcome'], 'deleted');
    expect(calls, <String>[
      'POST /rest/v1/rpc/admin_prepare_subject_deletion',
      'POST /rest/v1/rpc/admin_finalize_subject_deletion',
    ]);
  });

  test('missing Storage object is an idempotent deletion success', () async {
    final calls = <String>[];
    final client = SupabaseClient(
      baseUrl,
      apiKey,
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/admin_prepare_material_deletion')) {
          return _jsonResponse(<String, Object?>{
            'outcome': 'prepared',
            'job_id': jobId,
            'material_id': materialId,
            'subject_id': subjectId,
            'storage_paths': <String>[storagePath],
          }, request: request);
        }
        if (request.url.path == '/storage/v1/object/subject-materials') {
          return _jsonResponse(
            <String, Object?>{
              'message': 'Object not found',
              'error': 'not_found',
              'statusCode': '404',
            },
            request: request,
            statusCode: 404,
          );
        }
        if (request.url.path.endsWith('/admin_finalize_material_deletion')) {
          return _jsonResponse(<String, Object?>{
            'outcome': 'deleted',
            'job_id': jobId,
            'material_id': materialId,
            'deleted_materials': 1,
            'retired_quizzes': 0,
            'preserved_attempts': 0,
          }, request: request);
        }
        return _jsonResponse(
          <String, Object?>{'message': 'Unexpected test request'},
          request: request,
          statusCode: 500,
        );
      }),
    );
    addTearDown(client.dispose);

    final result = await BackendApiService(client: client)
        .deleteMaterialPermanently(
          materialId: materialId,
          expectedVersion: 4,
          reason: 'Permanent Admin deletion',
        );

    expect(result['outcome'], 'deleted');
    expect(calls, <String>[
      'POST /rest/v1/rpc/admin_prepare_material_deletion',
      'DELETE /storage/v1/object/subject-materials',
      'POST /rest/v1/rpc/admin_finalize_material_deletion',
    ]);
  });

  test('malformed finalizer response is never reported as success', () async {
    final calls = <String>[];
    final client = SupabaseClient(
      baseUrl,
      apiKey,
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/admin_prepare_material_deletion')) {
          return _jsonResponse(<String, Object?>{
            'outcome': 'prepared',
            'job_id': jobId,
            'material_id': materialId,
            'subject_id': subjectId,
            'storage_paths': <String>[storagePath],
          }, request: request);
        }
        if (request.url.path == '/storage/v1/object/subject-materials') {
          return _jsonResponse(const <Object?>[], request: request);
        }
        if (request.url.path.endsWith('/admin_finalize_material_deletion')) {
          return _jsonResponse(<String, Object?>{
            'outcome': 'deleted',
            'job_id': jobId,
            'material_id': materialId,
            'deleted_materials': 0,
          }, request: request);
        }
        return _jsonResponse(const <String, Object?>{}, request: request);
      }),
    );
    addTearDown(client.dispose);

    await expectLater(
      BackendApiService(client: client).deleteMaterialPermanently(
        materialId: materialId,
        expectedVersion: 4,
        reason: 'Permanent Admin deletion',
      ),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
    expect(calls, hasLength(3));
  });

  test('path outside the prepared target is rejected before Storage', () async {
    const otherSubjectId = '44444444-4444-4444-8444-444444444444';
    final calls = <String>[];
    final client = SupabaseClient(
      baseUrl,
      apiKey,
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return _jsonResponse(<String, Object?>{
          'outcome': 'prepared',
          'job_id': jobId,
          'material_id': materialId,
          'subject_id': subjectId,
          'storage_paths': <String>['$otherSubjectId/$materialId/notes.pdf'],
        }, request: request);
      }),
    );
    addTearDown(client.dispose);

    await expectLater(
      BackendApiService(client: client).deleteMaterialPermanently(
        materialId: materialId,
        expectedVersion: 4,
        reason: 'Permanent Admin deletion',
      ),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
    expect(calls, <String>[
      'POST /rest/v1/rpc/admin_prepare_material_deletion',
    ]);
  });
}

http.Response _jsonResponse(
  Object? body, {
  required http.BaseRequest request,
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    request: request,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
