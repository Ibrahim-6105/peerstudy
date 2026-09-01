import 'package:flutter_test/flutter_test.dart';
import 'package:peerstudy/providers/quiz_provider.dart';

void main() {
  test(
    'does not generate until one Material is selected and Start is called',
    () async {
      var generationCount = 0;
      late String capturedSubjectId;
      late String capturedMaterialId;
      late String capturedKey;
      final controller = SubjectQuizController(
        subjectId: 'subject-uuid',
        generationCall:
            ({
              required subjectId,
              required materialId,
              required idempotencyKey,
            }) async {
              generationCount += 1;
              capturedSubjectId = subjectId;
              capturedMaterialId = materialId;
              capturedKey = idempotencyKey;
              return _quizResponse(subjectId, materialId);
            },
      );

      expect(controller.state.status, QuizLoadStatus.choosingMaterial);
      expect(generationCount, 0);

      controller.selectMaterial('material-uuid');
      expect(controller.state.selectedMaterialId, 'material-uuid');
      expect(generationCount, 0);

      await controller.start();

      expect(generationCount, 1);
      expect(capturedSubjectId, 'subject-uuid');
      expect(capturedMaterialId, 'material-uuid');
      expect(_isUuid(capturedKey), isTrue);
      expect(controller.state.status, QuizLoadStatus.ready);
      expect(controller.state.attempt!.questions, hasLength(10));
      expect(controller.state.hasIncompleteQuiz, isTrue);
    },
  );

  test(
    'submits ten answers and exposes score with correction feedback',
    () async {
      late String submittedQuizId;
      late List<int> submittedAnswers;
      late String submissionKey;
      final controller = SubjectQuizController(
        subjectId: 'subject-uuid',
        generationCall:
            ({
              required subjectId,
              required materialId,
              required idempotencyKey,
            }) async => _quizResponse(subjectId, materialId),
        submissionCall:
            ({
              required quizId,
              required answers,
              required idempotencyKey,
            }) async {
              submittedQuizId = quizId;
              submittedAnswers = answers;
              submissionKey = idempotencyKey;
              return _resultResponse();
            },
      );
      controller.selectMaterial('material-uuid');
      await controller.start();
      for (var index = 0; index < 10; index++) {
        controller.selectAnswer(index, index % 4);
      }

      await controller.submit();

      expect(submittedQuizId, 'quiz-uuid');
      expect(submittedAnswers, List<int>.generate(10, (index) => index % 4));
      expect(_isUuid(submissionKey), isTrue);
      expect(controller.state.status, QuizLoadStatus.completed);
      expect(controller.state.result!.score, 7);
      expect(controller.state.result!.corrections, hasLength(10));
      expect(controller.state.hasIncompleteQuiz, isFalse);
    },
  );

  test('requires explicit confirmation state only after generation', () async {
    final controller = SubjectQuizController(
      subjectId: 'subject-uuid',
      generationCall:
          ({
            required subjectId,
            required materialId,
            required idempotencyKey,
          }) async => _quizResponse(subjectId, materialId),
    );

    controller.selectMaterial('material-uuid');
    expect(controller.state.hasIncompleteQuiz, isFalse);
    await controller.start();
    expect(controller.state.hasIncompleteQuiz, isTrue);

    controller.abandonIncompleteQuiz();
    expect(controller.state.status, QuizLoadStatus.choosingMaterial);
    expect(controller.state.attempt, isNull);
    expect(controller.state.hasIncompleteQuiz, isFalse);
  });
}

Map<Object?, Object?> _quizResponse(String subjectId, String materialId) {
  return <Object?, Object?>{
    'quiz_id': 'quiz-uuid',
    'subject_id': subjectId,
    'material_id': materialId,
    'title': 'Practice Quiz',
    'total': 10,
    'questions': List<Map<Object?, Object?>>.generate(10, (index) {
      return <Object?, Object?>{
        'id': 'q${index + 1}',
        'prompt': 'Question ${index + 1}',
        'options': const ['A', 'B', 'C', 'D'],
        'source_page': index + 1,
      };
    }),
  };
}

Map<Object?, Object?> _resultResponse() {
  return <Object?, Object?>{
    'score': 7,
    'total': 10,
    'submitted_at': '2030-01-01T00:00:00.000Z',
    'corrections': List<Map<Object?, Object?>>.generate(10, (index) {
      return <Object?, Object?>{
        'question_id': 'q${index + 1}',
        'selected_option': index % 4,
        'correct_option': index < 7 ? index % 4 : (index + 1) % 4,
        'selected_answer': 'Selected',
        'correct_answer': 'Correct',
        'explanation': 'Grounded feedback',
        'source_material_id': 'material-uuid',
        'source_page': index + 1,
      };
    }),
  };
}

bool _isUuid(String value) {
  return RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(value);
}
