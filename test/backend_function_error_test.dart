// These tests prove Edge Function errors stay readable and never expose raw
// transport objects or unreviewed proxy responses to a Student.

import 'package:flutter_test/flutter_test.dart';
import 'package:peerstudy/services/backend_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  // A normal Edge error keeps the server's reviewed message and stable fields.
  test('maps structured Edge Function details', () {
    const functionError = FunctionsHttpException(
      status: 503,
      details: <String, Object?>{
        'error': 'The configured AI quiz model is unavailable.',
        'code': 'ai-model-unavailable',
        'request_id': 'request-12345678',
      },
    );

    final mapped = backendExceptionFromFunction(functionError);

    expect(mapped.message, 'The configured AI quiz model is unavailable.');
    expect(mapped.code, 'ai-model-unavailable');
    expect(mapped.requestId, 'request-12345678');
    expect(mapped.httpStatus, 503);
  });

  // Some relays deliver JSON text instead of an already decoded Dart Map.
  test('maps JSON text details without showing the SDK exception', () {
    const functionError = FunctionsHttpException(
      status: 429,
      details:
          '{"error":"Wait before generating another quiz.","code":"ai-rate-limited"}',
    );

    final mapped = backendExceptionFromFunction(functionError);

    expect(mapped.message, 'Wait before generating another quiz.');
    expect(mapped.code, 'ai-rate-limited');
    expect(mapped.httpStatus, 429);
  });

  // Connection exception details may contain platform/network implementation
  // text, so the mapper must replace them with one reviewed message.
  test('maps a transport failure to a safe connection message', () {
    const functionError = FunctionsFetchException(
      details: 'socket failed with internal implementation details',
    );

    final mapped = backendExceptionFromFunction(functionError);

    expect(mapped.code, 'network-error');
    expect(mapped.httpStatus, 0);
    expect(mapped.message, contains('could not be reached'));
    expect(mapped.message, isNot(contains('socket failed')));
  });

  // Unstructured gateway output is never displayed directly.
  test('uses a safe fallback for an unstructured server error', () {
    const functionError = FunctionsHttpException(
      status: 503,
      details: '<html>private gateway failure</html>',
    );

    final mapped = backendExceptionFromFunction(functionError);

    expect(mapped.code, 'function-error');
    expect(mapped.message, contains('temporarily unavailable'));
    expect(mapped.message, isNot(contains('private gateway')));
  });
}
