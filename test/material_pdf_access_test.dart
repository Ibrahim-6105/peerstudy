import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peerstudy/models/subject.dart';
import 'package:peerstudy/screens/student/material_viewer_screen.dart';
import 'package:peerstudy/services/backend_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const baseUrl = 'https://peerstudy.test';
  const apiKey = 'test-publishable-key';
  const userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const subjectId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const materialId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const storagePath = '$subjectId/$materialId/lecture.pdf';

  test(
    'approved PDF creates one signed URL without downloading bytes',
    () async {
      const checksum =
          '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';
      final calls = <String>[];
      final client = SupabaseClient(
        baseUrl,
        apiKey,
        httpClient: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');

          if (request.url.path == '/rest/v1/subject_materials') {
            expect(
              request.headers['authorization'],
              'Bearer test-access-token',
            );
            return _jsonResponse(
              _materialRow(checksum: checksum, sizeBytes: 2 * 1024 * 1024),
              request: request,
            );
          }

          if (request.url.path ==
              '/storage/v1/object/sign/subject-materials/$storagePath') {
            expect(request.method, 'POST');
            expect(
              request.headers['authorization'],
              'Bearer test-access-token',
            );
            expect(jsonDecode(request.body), <String, Object?>{
              'expiresIn': 600,
            });
            return _jsonResponse(<String, Object?>{
              'signedURL':
                  '/object/sign/subject-materials/$storagePath?token=test-token',
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
      await _restoreTestSession(client, userId: userId);

      final uri = await BackendApiService(
        client: client,
      ).requestMaterialAccess(materialId);

      expect(uri.scheme, 'https');
      expect(uri.host, 'peerstudy.test');
      expect(uri.queryParameters['token'], 'test-token');
      expect(uri.queryParameters['cacheNonce'], checksum);
      expect(calls, <String>[
        'GET /rest/v1/subject_materials',
        'POST /storage/v1/object/sign/subject-materials/$storagePath',
      ]);
      expect(
        calls.where(
          (call) =>
              call == 'GET /storage/v1/object/subject-materials/$storagePath',
        ),
        isEmpty,
      );
    },
  );

  test('invalid material metadata is rejected before signing', () async {
    final calls = <String>[];
    final client = SupabaseClient(
      baseUrl,
      apiKey,
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/rest/v1/subject_materials') {
          return _jsonResponse(
            _materialRow(checksum: 'not-a-sha256', sizeBytes: 1024),
            request: request,
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

    await expectLater(
      BackendApiService(client: client).requestMaterialAccess(materialId),
      throwsA(
        isA<BackendException>()
            .having((error) => error.code, 'code', 'failed-precondition')
            .having(
              (error) => error.message,
              'message',
              contains('approved PDF'),
            ),
      ),
    );
    expect(calls, <String>['GET /rest/v1/subject_materials']);
  });

  test(
    'deleted or inaccessible material returns a safe not-found error',
    () async {
      final client = SupabaseClient(
        baseUrl,
        apiKey,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/subject_materials');
          return _jsonResponse(<Object?>[], request: request);
        }),
      );
      addTearDown(client.dispose);
      await _restoreTestSession(client, userId: userId);

      await expectLater(
        BackendApiService(client: client).requestMaterialAccess(materialId),
        throwsA(
          isA<BackendException>()
              .having((error) => error.code, 'code', 'not-found')
              .having(
                (error) => error.message,
                'message',
                contains('no longer available'),
              ),
        ),
      );
    },
  );

  test('invalid material ID is rejected without a network request', () async {
    var requested = false;
    final client = SupabaseClient(
      baseUrl,
      apiKey,
      httpClient: MockClient((request) async {
        requested = true;
        return _jsonResponse(<Object?>[], request: request);
      }),
    );
    addTearDown(client.dispose);

    await expectLater(
      BackendApiService(client: client).requestMaterialAccess('not-a-uuid'),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          'invalid-argument',
        ),
      ),
    );
    expect(requested, isFalse);
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

  testWidgets('shared opener launches one external viewer after rapid taps', (
    tester,
  ) async {
    final accessGate = Completer<Uri>();
    const signedUri = 'https://peerstudy.test/lecture.pdf?token=temporary';
    var accessRequests = 0;
    var launchRequests = 0;
    late BuildContext sourceContext;
    Future<void>? opening;

    Future<Uri> loadAccess(String materialId) {
      accessRequests += 1;
      return accessGate.future;
    }

    Future<bool> launchExternally(Uri uri) async {
      launchRequests += 1;
      expect(uri, Uri.parse(signedUri));
      return true;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            sourceContext = context;
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  opening = MaterialViewerScreen.open(
                    context,
                    material: _testMaterial(),
                    accessLoader: loadAccess,
                    externalLauncher: launchExternally,
                  );
                },
                child: const Text('Open lecture'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open lecture'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(accessRequests, 1);
    expect(find.byType(MaterialViewerScreen), findsOneWidget);
    expect(find.text('Opening secure lecture PDF...'), findsOneWidget);

    // Simulate another source-card tap while the first request is unresolved.
    await MaterialViewerScreen.open(
      sourceContext,
      material: _testMaterial(),
      accessLoader: loadAccess,
      externalLauncher: launchExternally,
    );
    expect(accessRequests, 1);

    accessGate.complete(Uri.parse(signedUri));
    await tester.pumpAndSettle();
    await opening;

    expect(launchRequests, 1);
    expect(find.text('Open lecture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external launch failure shows a retry instead of a red screen', (
    tester,
  ) async {
    var accessRequests = 0;
    var launchRequests = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MaterialViewerScreen(
          material: _testMaterial(),
          accessLoader: (materialId) async {
            accessRequests += 1;
            return Uri.parse('https://peerstudy.test/lecture.pdf?token=test');
          },
          externalLauncher: (uri) async {
            launchRequests += 1;
            return launchRequests > 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('could not be opened in your PDF app or browser'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(accessRequests, 2);
    expect(launchRequests, 2);
    expect(find.text('The lecture PDF opened securely.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing lecture displays the safe backend message', (
    tester,
  ) async {
    var launched = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MaterialViewerScreen(
          material: _testMaterial(),
          accessLoader: (materialId) async => throw const BackendException(
            'This lecture is no longer available for your account.',
            code: 'not-found',
          ),
          externalLauncher: (uri) async {
            launched = true;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This lecture is no longer available for your account.'),
      findsOneWidget,
    );
    expect(launched, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('official viewer uses the reliable external signed-link path', () {
    final viewer = File(
      'lib/screens/student/material_viewer_screen.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/backend_api_service.dart',
    ).readAsStringSync();
    final accessSection = _section(
      service,
      'Future<Uri> requestMaterialAccess',
      'Future<SignedUploadSession> createMaterialUpload',
    );

    expect(viewer, contains('LaunchMode.externalApplication'));
    expect(viewer, contains('_activeMaterialIds'));
    expect(viewer, isNot(contains('PdfViewer.')));
    expect(viewer, isNot(contains('pdfrx')));
    expect(accessSection, contains(".from('subject-materials')"));
    expect(accessSection, contains('createSignedUrl(path, 600'));
    expect(accessSection, isNot(contains('.download(')));
  });

  test('Student and Admin material lists use the same guarded opener', () {
    final dashboard = File(
      'lib/screens/admin/admin_dashboard_screen.dart',
    ).readAsStringSync();
    final studentWorkspace = File(
      'lib/screens/student/student_subject_workspace_screen.dart',
    ).readAsStringSync();

    expect(dashboard, contains("tooltip: 'Open PDF'"));
    expect(dashboard, contains('MaterialViewerScreen.open('));
    expect(studentWorkspace, contains('MaterialViewerScreen.open('));
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
      '// DepartmentFormPage',
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
      'Future<void> _deleteDepartment',
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

StudyMaterial _testMaterial() => StudyMaterial(
  id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  subjectId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  title: 'Test lecture',
  storagePath:
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/'
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc/lecture.pdf',
  version: 1,
  status: 'approved',
  mimeType: 'application/pdf',
  sizeBytes: 1024,
  checksum: '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
  updatedAt: DateTime.utc(2026, 1, 1),
);

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
