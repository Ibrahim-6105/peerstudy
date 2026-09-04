import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peerstudy/services/backend_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const baseUrl = 'https://peerstudy.test';
  const apiKey = 'test-publishable-key';
  const userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const subjectId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const materialId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const storagePath = '$subjectId/$materialId/lecture.pdf';

  test('approved PDF uses one authenticated full Storage download', () async {
    final bytes = _validPdfBytes();
    final checksum = sha256.convert(bytes).toString();
    final calls = <String>[];
    final client = SupabaseClient(
      baseUrl,
      apiKey,
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');

        if (request.url.path == '/rest/v1/subject_materials') {
          expect(request.headers['authorization'], 'Bearer test-access-token');
          return _jsonResponse(
            _materialRow(checksum: checksum, sizeBytes: bytes.length),
            request: request,
          );
        }

        if (request.url.path ==
            '/storage/v1/object/subject-materials/$storagePath') {
          expect(request.method, 'GET');
          expect(request.headers['authorization'], 'Bearer test-access-token');
          expect(request.url.queryParameters['cacheNonce'], checksum);
          return http.Response.bytes(
            bytes,
            200,
            request: request,
            headers: const <String, String>{'content-type': 'application/pdf'},
          );
        }

        return _jsonResponse(
          <String, Object?>{'message': 'Unexpected test request'},
          request: request,
          statusCode: 500,
        );
      }),
    );
    addTearDown(client.dispose);
    await _restoreTestSession(client, userId: userId);

    final access = await BackendApiService(
      client: client,
    ).requestMaterialAccess(materialId);

    expect(access.materialId, materialId);
    expect(access.bytes, bytes);
    expect(access.checksum, checksum);
    expect(access.sourceName, '$materialId-3-$checksum.pdf');
    expect(calls, <String>[
      'GET /rest/v1/subject_materials',
      'GET /storage/v1/object/subject-materials/$storagePath',
    ]);
    expect(calls.where((call) => call.contains('/object/sign/')), isEmpty);
  });

  test('downloaded PDF with a mismatched checksum is rejected', () async {
    final bytes = _validPdfBytes();
    final wrongChecksum = sha256.convert(<int>[1, 2, 3]).toString();
    final client = SupabaseClient(
      baseUrl,
      apiKey,
      httpClient: MockClient((request) async {
        if (request.url.path == '/rest/v1/subject_materials') {
          return _jsonResponse(
            _materialRow(checksum: wrongChecksum, sizeBytes: bytes.length),
            request: request,
          );
        }
        if (request.url.path ==
            '/storage/v1/object/subject-materials/$storagePath') {
          return http.Response.bytes(bytes, 200, request: request);
        }
        return _jsonResponse(
          <String, Object?>{'message': 'Unexpected test request'},
          request: request,
          statusCode: 500,
        );
      }),
    );
    addTearDown(client.dispose);
    await _restoreTestSession(client, userId: userId);

    await expectLater(
      BackendApiService(client: client).requestMaterialAccess(materialId),
      throwsA(
        isA<BackendException>()
            .having((error) => error.code, 'code', 'invalid-pdf')
            .having((error) => error.message, 'message', contains('integrity')),
      ),
    );
  });

  test('Admin upload rejects a renamed non-PDF before Storage', () async {
    final calls = <String>[];
    final client = SupabaseClient(
      baseUrl,
      apiKey,
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return _jsonResponse(
          <String, Object?>{'message': 'Unexpected test request'},
          request: request,
          statusCode: 500,
        );
      }),
    );
    addTearDown(client.dispose);
    await _restoreTestSession(client, userId: userId);

    final session = SignedUploadSession(
      uploadId: materialId,
      materialId: materialId,
      uploadUrl: Uri.parse(
        '$baseUrl/storage/v1/object/subject-materials/$storagePath',
      ),
      requiredHeaders: const <String, String>{},
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      storagePath: storagePath,
    );
    final invalidBytes = Uint8List.fromList(utf8.encode('not really a PDF'));

    await expectLater(
      BackendApiService(client: client).uploadMaterialStream(
        session: session,
        bytes: Stream<List<int>>.value(invalidBytes),
        sizeBytes: invalidBytes.length,
      ),
      throwsA(
        isA<BackendException>()
            .having((error) => error.code, 'code', 'invalid-file')
            .having((error) => error.message, 'message', contains('readable')),
      ),
    );
    expect(calls, isEmpty);
  });

  test('official viewer renders verified bytes without URI range access', () {
    final viewer = File(
      'lib/screens/student/material_viewer_screen.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/backend_api_service.dart',
    ).readAsStringSync();
    final accessSection = _section(
      service,
      'Future<MaterialAccess> requestMaterialAccess',
      'Future<SignedUploadSession> createMaterialUpload',
    );

    expect(viewer, contains('PdfViewer.data('));
    expect(viewer, contains('access.bytes'));
    expect(viewer, isNot(contains('PdfViewer.uri(')));
    expect(viewer, isNot(contains('preferRangeAccess')));
    expect(accessSection, contains(".from('subject-materials')"));
    expect(accessSection, contains('.download(path, cacheNonce: checksum)'));
    expect(accessSection, isNot(contains('createSignedUrl')));
  });

  test('Admin material list exposes the shared Open PDF viewer', () {
    final dashboard = File(
      'lib/screens/admin/admin_dashboard_screen.dart',
    ).readAsStringSync();

    expect(dashboard, contains("tooltip: 'Open PDF'"));
    expect(dashboard, contains('MaterialViewerScreen(material: material)'));
    expect(dashboard, contains('StudyMaterial.fromSupabase(row)'));
  });

  test('Storage read policy allows Admin and approved Student access', () {
    final migration = File(
      'supabase/migrations/20260828000100_peerstudy_corrected_master.sql',
    ).readAsStringSync();
    final readPolicy = _section(
      migration,
      'create policy subject_materials_objects_read',
      'drop policy if exists subject_materials_objects_insert',
    );

    expect(readPolicy, contains('public.is_admin()'));
    expect(readPolicy, contains("m.status = 'approved'"));
    expect(readPolicy, contains('public.can_access_subject(m.subject_id)'));
  });

  test('PDF and Subject forms omit display order and PDF version labels', () {
    final forms = File(
      'lib/screens/admin/admin_form_pages.dart',
    ).readAsStringSync();
    final subjectValue = _section(
      forms,
      'class SubjectFormValue',
      '// MaterialFormValue',
    );
    final subjectPage = _section(
      forms,
      'class SubjectFormPage',
      '// MaterialFormPage',
    );
    final materialForm = _section(
      forms,
      'class MaterialFormValue',
      '// AcademicAreaFormPage',
    );
    final materialPage = _section(
      forms,
      'class MaterialFormPage',
      '// _AdminFormFrame',
    );
    final service = File(
      'lib/services/backend_api_service.dart',
    ).readAsStringSync();
    final uploadApi = _section(
      service,
      'Future<SignedUploadSession> createMaterialUpload',
      'Future<Map<Object?, Object?>> finalizeMaterialUpload',
    );
    final studentWorkspace = File(
      'lib/screens/student/student_subject_workspace_screen.dart',
    ).readAsStringSync();
    final dashboard = File(
      'lib/screens/admin/admin_dashboard_screen.dart',
    ).readAsStringSync();
    final subjectWrite = _section(
      dashboard,
      'Future<void> _editSubject',
      'Future<void> _deleteCatalogRow',
    );
    final provider = File(
      'lib/providers/subject_provider.dart',
    ).readAsStringSync();
    final subjectRead = _section(
      provider,
      'Future<List<StudySubject>> fetchSubjects',
      'Future<List<StudyMaterial>> fetchMaterials',
    );

    expect(subjectValue, isNot(contains('displayOrder')));
    expect(subjectPage, isNot(contains('Display order')));
    expect(subjectPage, isNot(contains('_orderController')));
    expect(subjectWrite, isNot(contains('p_display_order')));
    expect(subjectWrite, isNot(contains("'display_order'")));
    expect(subjectRead, isNot(contains(".order('display_order')")));
    expect(subjectRead, contains(".order('name')"));
    expect(materialForm, isNot(contains('displayOrder')));
    expect(materialPage, isNot(contains('Display order')));
    expect(materialPage, isNot(contains('_orderController')));
    expect(uploadApi, isNot(contains('displayOrder')));
    expect(studentWorkspace, isNot(contains(r'Version ${material.version}')));
  });
}

Uint8List _validPdfBytes() {
  return Uint8List.fromList(
    ascii.encode(
      '%PDF-1.4\n'
      '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
      'trailer\n<< /Root 1 0 R >>\n'
      '%%EOF\n',
    ),
  );
}

Map<String, Object?> _materialRow({
  required String checksum,
  required int sizeBytes,
}) {
  return <String, Object?>{
    'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'subject_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'storage_path':
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/'
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc/lecture.pdf',
    'version': 3,
    'checksum': checksum,
    'status': 'approved',
    'mime_type': 'application/pdf',
    'size_bytes': sizeBytes,
  };
}

Future<void> _restoreTestSession(
  SupabaseClient client, {
  required String userId,
}) async {
  await client.auth.recoverSession(
    jsonEncode(<String, Object?>{
      'access_token': 'test-access-token',
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': <String, Object?>{
        'id': userId,
        'app_metadata': const <String, Object?>{},
        'user_metadata': const <String, Object?>{},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00.000Z',
      },
    }),
  );
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

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing $end');
  return source.substring(startIndex, endIndex);
}
