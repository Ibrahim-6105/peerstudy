// Contract tests keep Flutter aligned with the corrected quiz API.

import 'package:flutter_test/flutter_test.dart';
import 'package:peerstudy/models/quiz.dart';

void main() {
  test('parses exactly ten answer-free grounded questions', () {
    final response = <Object?, Object?>{
      'attemptId': 'attempt-1',
      'subjectId': 'data-structures',
      'materialId': 'material-1',
      'expiresAt': '2030-01-01T00:00:00.000Z',
      'questions': List<Map<Object?, Object?>>.generate(10, (index) {
        return <Object?, Object?>{
          'id': 'q${index + 1}',
          'prompt': 'Question ${index + 1}',
          'options': const ['A', 'B', 'C', 'D'],
          'sourceMaterialId': 'material-1',
          'sourcePage': index + 1,
        };
      }),
    };

    final attempt = SubjectQuizAttempt.fromMap('data-structures', response);

    expect(attempt.questions, hasLength(10));
    expect(attempt.materialId, 'material-1');
    expect(attempt.questions.first.text, 'Question 1');
    expect(attempt.questions.first.sourceLabel, 'material-1 - page 1');
  });

  test('parses server scoring correction field names', () {
    final response = <Object?, Object?>{
      'score': 8,
      'total': 10,
      'submittedAt': '2030-01-01T00:00:00.000Z',
      'corrections': List<Map<Object?, Object?>>.generate(10, (index) {
        return <Object?, Object?>{
          'questionId': 'q${index + 1}',
          'selectedOption': index == 0 ? 1 : 0,
          'correctOption': 0,
          'explanation': 'Grounded explanation',
          'sourceMaterialId': 'material-1',
          'sourcePage': index + 1,
        };
      }),
    };

    final result = SubjectQuizResult.fromMap(response);

    expect(result.score, 8);
    expect(result.corrections, hasLength(10));
    expect(result.corrections.first.selectedIndex, 1);
    expect(result.corrections.first.correctIndex, 0);
  });

  test('rejects a malformed nine-question attempt', () {
    final response = <Object?, Object?>{
      'attemptId': 'attempt-1',
      'subjectId': 'data-structures',
      'materialId': 'material-1',
      'expiresAt': '2030-01-01T00:00:00.000Z',
      'questions': List<Map<Object?, Object?>>.generate(9, (index) {
        return <Object?, Object?>{
          'id': 'q$index',
          'prompt': 'Question',
          'options': const ['A', 'B', 'C', 'D'],
          'sourcePage': 1,
        };
      }),
    };

    expect(
      () => SubjectQuizAttempt.fromMap('data-structures', response),
      throwsFormatException,
    );
  });

  test('uses corrected snake-case quiz response and selected Material', () {
    final response = <Object?, Object?>{
      'quiz_id': 'quiz-uuid',
      'subject_id': 'subject-uuid',
      'material_id': 'material-uuid',
      'total': 10,
      'expires_at': '2030-01-01T00:00:00.000Z',
      'questions': List<Map<Object?, Object?>>.generate(10, (index) {
        return <Object?, Object?>{
          'id': 'q${index + 1}',
          'prompt': 'Question ${index + 1}',
          'options': const ['A', 'B', 'C', 'D'],
          'source_page': index + 1,
        };
      }),
    };

    final attempt = SubjectQuizAttempt.fromMap(
      'subject-uuid',
      response,
      requestedMaterialId: 'material-uuid',
    );

    expect(attempt.attemptId, 'quiz-uuid');
    expect(attempt.materialId, 'material-uuid');
    expect(
      attempt.questions.every(
        (question) => question.sourceMaterialId == 'material-uuid',
      ),
      isTrue,
    );
  });

  test('rejects a quiz returned for a different Material', () {
    final response = <Object?, Object?>{
      'quiz_id': 'quiz-uuid',
      'subject_id': 'subject-uuid',
      'material_id': 'other-material',
      'expires_at': '2030-01-01T00:00:00.000Z',
      'questions': List<Map<Object?, Object?>>.generate(10, (index) {
        return <Object?, Object?>{
          'id': 'q$index',
          'prompt': 'Question',
          'options': const ['A', 'B', 'C', 'D'],
          'source_page': 1,
        };
      }),
    };

    expect(
      () => SubjectQuizAttempt.fromMap(
        'subject-uuid',
        response,
        requestedMaterialId: 'selected-material',
      ),
      throwsFormatException,
    );
  });
}
