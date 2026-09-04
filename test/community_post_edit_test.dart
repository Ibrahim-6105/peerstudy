import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peerstudy/models/subject.dart';
import 'package:peerstudy/providers/academic_provider.dart';
import 'package:peerstudy/screens/student/subject_community_views.dart';
import 'package:peerstudy/services/backend_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Community post editor', () {
    testWidgets('saves and finishes its closing animation without an exception', (
      tester,
    ) async {
      String? submittedBody;
      await tester.pumpWidget(
        MaterialApp(
          home: _EditSheetHarness(onSave: (body) async => submittedBody = body),
        ),
      );

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '  Updated post  ');
      await tester.tap(find.text('Save'));

      // The original bug disposed the controller during this reverse animation.
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      expect(submittedBody, 'Updated post');
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the draft open and retryable after a backend failure', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: _EditSheetHarness(
            onSave: (body) async {
              calls += 1;
              if (calls == 1) {
                throw const BackendException(
                  'Could not reach the server. Check your connection and retry.',
                  code: 'network-error',
                );
              }
            },
          ),
        ),
      );

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Keep my draft');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('Keep my draft'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('community-edit-error')),
        findsOneWidget,
      );
      expect(find.text('Save'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('blocks duplicate saves while one request is running', (
      tester,
    ) async {
      final request = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: _EditSheetHarness(
            onSave: (body) {
              calls += 1;
              return request.future;
            },
          ),
        ),
      );

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Only one request');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(calls, 1);
      expect(
        find.byKey(const ValueKey<String>('community-edit-loading')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey<String>('community-edit-save')),
            )
            .onPressed,
        isNull,
      );

      // A programmatic second submission cannot bypass the synchronous guard.
      await tester.tap(
        find.byKey(const ValueKey<String>('community-edit-save')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(calls, 1);

      // System back cannot dismiss the editor and permit a duplicate request
      // while the first protected write is still unresolved.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('community-edit-loading')),
        findsOneWidget,
      );

      request.complete();
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rejects an empty edit without calling the backend', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: _EditSheetHarness(onSave: (body) async => calls += 1),
        ),
      );

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(calls, 0);
      expect(find.text('Write some text before saving.'), findsOneWidget);
      expect(find.text('Edit Community post'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Community post edit API', () {
    const baseUrl = 'https://peerstudy.test';
    const apiKey = 'test-publishable-key';
    const userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const subjectId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const postId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

    test(
      'sends the exact RPC contract and validates the next version',
      () async {
        var rpcCalls = 0;
        final client = SupabaseClient(
          baseUrl,
          apiKey,
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/rest/v1/rpc/update_community_post');
            expect(
              request.headers['authorization'],
              'Bearer test-access-token',
            );
            expect(jsonDecode(request.body), <String, Object?>{
              'p_post_id': postId,
              'p_expected_version': 4,
              'p_body': 'Updated safely',
            });
            rpcCalls += 1;
            return _jsonResponse(<Object?>[
              <String, Object?>{
                'id': postId,
                'community_id': subjectId,
                'body': 'Updated safely',
                'version': 5,
                'status': 'active',
                'is_removed': false,
              },
            ], request: request);
          }),
        );
        addTearDown(client.dispose);
        await _restoreTestSession(client, userId: userId);

        final result = await BackendApiService(client: client).editPost(
          subjectId: subjectId,
          postId: postId,
          expectedVersion: 4,
          body: '  Updated safely  ',
        );

        expect(rpcCalls, 1);
        expect(result['id'], postId);
        expect(result['version'], 5);
      },
    );

    test(
      'turns a stale-version database error into safe retry guidance',
      () async {
        final client = SupabaseClient(
          baseUrl,
          apiKey,
          httpClient: MockClient((request) async {
            return _jsonResponse(
              <String, Object?>{
                'code': '40001',
                'message': 'Post version conflict',
                'details': null,
                'hint': null,
              },
              request: request,
              statusCode: 400,
            );
          }),
        );
        addTearDown(client.dispose);
        await _restoreTestSession(client, userId: userId);

        await expectLater(
          BackendApiService(client: client).editPost(
            subjectId: subjectId,
            postId: postId,
            expectedVersion: 4,
            body: 'Updated safely',
          ),
          throwsA(
            isA<BackendException>()
                .having((error) => error.code, 'code', 'version-conflict')
                .having(
                  (error) => error.message,
                  'message',
                  contains('reopen Edit'),
                ),
          ),
        );
      },
    );

    test(
      'rejects a response that did not advance the requested version',
      () async {
        final client = SupabaseClient(
          baseUrl,
          apiKey,
          httpClient: MockClient((request) async {
            return _jsonResponse(<String, Object?>{
              'id': postId,
              'community_id': subjectId,
              'body': 'Updated safely',
              'version': 4,
              'status': 'active',
              'is_removed': false,
            }, request: request);
          }),
        );
        addTearDown(client.dispose);
        await _restoreTestSession(client, userId: userId);

        await expectLater(
          BackendApiService(client: client).editPost(
            subjectId: subjectId,
            postId: postId,
            expectedVersion: 4,
            body: 'Updated safely',
          ),
          throwsA(
            isA<BackendException>().having(
              (error) => error.code,
              'code',
              'invalid-response',
            ),
          ),
        );
      },
    );
  });

  group('Community edit controller', () {
    const baseUrl = 'https://peerstudy.test';
    const apiKey = 'test-publishable-key';
    const userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const subjectId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const postId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

    test(
      'rejects a stale visible version without sending an edit RPC',
      () async {
        var editRpcCalls = 0;
        var postReads = 0;
        final client = SupabaseClient(
          baseUrl,
          apiKey,
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/communities') {
              return _jsonResponse(<String, Object?>{
                'id': subjectId,
              }, request: request);
            }
            if (request.url.path == '/rest/v1/community_posts') {
              postReads += 1;
              return _jsonResponse(<Object?>[
                _postRow(
                  postId: postId,
                  subjectId: subjectId,
                  userId: userId,
                  body: 'Original post',
                  version: 1,
                ),
              ], request: request);
            }
            if (request.url.path == '/rest/v1/community_comments' ||
                request.url.path == '/rest/v1/community_attachments') {
              return _jsonResponse(<Object?>[], request: request);
            }
            if (request.url.path == '/rest/v1/rpc/update_community_post') {
              editRpcCalls += 1;
            }
            return _unexpectedResponse(request);
          }),
        );
        addTearDown(client.dispose);
        await _restoreTestSession(client, userId: userId);
        final controller = _controller(client);
        addTearDown(controller.dispose);
        await controller.watchCommunity(_subject(subjectId, code: 'SUB-1'));

        await expectLater(
          controller.updatePost(
            postId: postId,
            expectedVersion: 2,
            body: 'Must not overwrite',
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('changed while you were editing'),
            ),
          ),
        );

        expect(editRpcCalls, 0);
        expect(postReads, 1);
        expect(controller.state.posts.single.body, 'Original post');
      },
    );

    test(
      'stale refresh cannot overwrite an edit when the next refresh fails',
      () async {
        var postReads = 0;
        var commentReads = 0;
        final staleSnapshotReady = Completer<void>();
        final releaseStaleSnapshot = Completer<void>();
        final editRpcRequested = Completer<void>();
        final client = SupabaseClient(
          baseUrl,
          apiKey,
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/communities') {
              return _jsonResponse(<String, Object?>{
                'id': subjectId,
              }, request: request);
            }
            if (request.url.path == '/rest/v1/community_posts') {
              postReads += 1;
              if (postReads > 2) {
                return _jsonResponse(
                  <String, Object?>{
                    'code': 'PGRST000',
                    'message': 'Temporary connection failure',
                  },
                  request: request,
                  statusCode: 400,
                );
              }
              return _jsonResponse(<Object?>[
                _postRow(
                  postId: postId,
                  subjectId: subjectId,
                  userId: userId,
                  body: 'Original post',
                  version: 1,
                ),
              ], request: request);
            }
            if (request.url.path == '/rest/v1/community_comments') {
              commentReads += 1;
              if (commentReads == 2) {
                staleSnapshotReady.complete();
                await releaseStaleSnapshot.future;
              }
              return _jsonResponse(<Object?>[], request: request);
            }
            if (request.url.path == '/rest/v1/community_attachments') {
              return _jsonResponse(<Object?>[], request: request);
            }
            if (request.url.path == '/rest/v1/rpc/update_community_post') {
              editRpcRequested.complete();
              return _jsonResponse(<String, Object?>{
                ..._postRow(
                  postId: postId,
                  subjectId: subjectId,
                  userId: userId,
                  body: 'Confirmed edit',
                  version: 2,
                ),
                'updated_at': '2026-09-04T12:05:00.000Z',
              }, request: request);
            }
            return _unexpectedResponse(request);
          }),
        );
        addTearDown(client.dispose);
        await _restoreTestSession(client, userId: userId);
        final controller = _controller(client);
        addTearDown(controller.dispose);
        await controller.watchCommunity(_subject(subjectId, code: 'SUB-1'));

        final staleRefresh = controller.refresh();
        await staleSnapshotReady.future;
        final edit = controller.updatePost(
          postId: postId,
          expectedVersion: 1,
          body: 'Confirmed edit',
        );
        await editRpcRequested.future;
        try {
          // The post-edit refresh must bypass the blocked pre-edit snapshot.
          await edit.timeout(const Duration(seconds: 2));
        } finally {
          if (!releaseStaleSnapshot.isCompleted) {
            releaseStaleSnapshot.complete();
          }
        }
        await staleRefresh;

        expect(postReads, 3);
        expect(controller.state.posts.single.body, 'Confirmed edit');
        expect(controller.state.posts.single.version, 2);
        expect(controller.state.errorMessage, contains('Temporary connection'));
      },
    );

    test(
      'never publishes an old Subject response after switching Subjects',
      () async {
        const secondSubjectId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
        const secondPostId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
        final oldPostStarted = Completer<void>();
        final newPostStarted = Completer<void>();
        final releaseOldPost = Completer<void>();
        final client = SupabaseClient(
          baseUrl,
          apiKey,
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/communities') {
              final filter = request.url.queryParameters['subject_id'] ?? '';
              final selectedId = filter.contains(secondSubjectId)
                  ? secondSubjectId
                  : subjectId;
              return _jsonResponse(<String, Object?>{
                'id': selectedId,
              }, request: request);
            }
            if (request.url.path == '/rest/v1/community_posts') {
              final filter = request.url.queryParameters['community_id'] ?? '';
              if (filter.contains(subjectId) &&
                  !filter.contains(secondSubjectId)) {
                if (!oldPostStarted.isCompleted) oldPostStarted.complete();
                await releaseOldPost.future;
                return _jsonResponse(<Object?>[
                  _postRow(
                    postId: postId,
                    subjectId: subjectId,
                    userId: userId,
                    body: 'Old Subject post',
                    version: 1,
                  ),
                ], request: request);
              }
              if (!newPostStarted.isCompleted) newPostStarted.complete();
              return _jsonResponse(<Object?>[
                _postRow(
                  postId: secondPostId,
                  subjectId: secondSubjectId,
                  userId: userId,
                  body: 'New Subject post',
                  version: 1,
                ),
              ], request: request);
            }
            if (request.url.path == '/rest/v1/community_comments' ||
                request.url.path == '/rest/v1/community_attachments') {
              return _jsonResponse(<Object?>[], request: request);
            }
            return _unexpectedResponse(request);
          }),
        );
        addTearDown(client.dispose);
        await _restoreTestSession(client, userId: userId);
        final controller = _controller(client);
        addTearDown(controller.dispose);

        final oldWatch = controller.watchCommunity(
          _subject(subjectId, code: 'SUB-1'),
        );
        await oldPostStarted.future;
        final newWatch = controller.watchCommunity(
          _subject(secondSubjectId, code: 'SUB-2'),
        );

        // The new generation must issue its own query without waiting for the
        // deliberately blocked old-Subject request.
        await newPostStarted.future.timeout(const Duration(seconds: 2));
        await newWatch;
        expect(controller.state.posts.single.id, secondPostId);

        releaseOldPost.complete();
        await oldWatch;

        expect(controller.state.activeCommunityId, secondSubjectId);
        expect(controller.state.posts, hasLength(1));
        expect(controller.state.posts.single.id, secondPostId);
        expect(controller.state.posts.single.body, 'New Subject post');
        expect(controller.state.isLive, isTrue);
      },
    );
  });
}

class _EditSheetHarness extends StatefulWidget {
  const _EditSheetHarness({required this.onSave});

  final Future<void> Function(String body) onSave;

  @override
  State<_EditSheetHarness> createState() => _EditSheetHarnessState();
}

class _EditSheetHarnessState extends State<_EditSheetHarness> {
  bool? _saved;

  Future<void> _open() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => CommunityEditTextSheet(
        title: 'Edit Community post',
        initialValue: 'Original post',
        maxLength: 5000,
        failureMessage: 'The post could not be edited.',
        onSave: widget.onSave,
      ),
    );
    if (mounted) setState(() => _saved = saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          FilledButton(onPressed: _open, child: const Text('Open editor')),
          Text(_saved == true ? 'Saved' : 'Not saved'),
        ],
      ),
    );
  }
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

http.Response _unexpectedResponse(http.BaseRequest request) {
  return _jsonResponse(
    <String, Object?>{
      'code': 'unexpected',
      'message': 'Unexpected test request: ${request.url}',
    },
    request: request,
    statusCode: 500,
  );
}

CommunityController _controller(SupabaseClient client) {
  return CommunityController(
    client: client,
    repository: CommunityRepository(backend: BackendApiService(client: client)),
  );
}

StudySubject _subject(String id, {required String code}) {
  return StudySubject(
    id: id,
    areaId: '11111111-1111-4111-8111-111111111111',
    departmentId: '22222222-2222-4222-8222-222222222222',
    code: code,
    name: code,
    description: '',
    status: 'active',
  );
}

Map<String, Object?> _postRow({
  required String postId,
  required String subjectId,
  required String userId,
  required String body,
  required int version,
}) {
  return <String, Object?>{
    'id': postId,
    'community_id': subjectId,
    'author_id': userId,
    'author_name': 'Test Student',
    'body': body,
    'version': version,
    'status': 'active',
    'is_removed': false,
    'is_reported': false,
    'created_at': '2026-09-04T12:00:00.000Z',
    'updated_at': '2026-09-04T12:00:00.000Z',
  };
}
