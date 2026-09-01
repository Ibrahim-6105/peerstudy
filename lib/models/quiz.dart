// Typed models for one approved-material, ten-question practice quiz.
//
// Beginner note:
// The backend keeps every answer key private while the quiz is in progress.
// The phone receives corrections only after all answers are submitted.

class SubjectQuizQuestion {
  const SubjectQuizQuestion({
    required this.id,
    required this.text,
    required this.options,
    required this.sourceLabel,
    required this.sourceMaterialId,
    required this.sourcePage,
  });

  final String id;
  final String text;
  final List<String> options;
  final String sourceLabel;
  final String sourceMaterialId;
  final int sourcePage;

  factory SubjectQuizQuestion.fromMap(Map<Object?, Object?> data) {
    final rawOptions = data['options'];
    final options = rawOptions is List
        ? rawOptions.map((item) => item.toString().trim()).toList()
        : const <String>[];
    final sourceMaterialId = _text(
      data['sourceMaterialId'] ?? data['source_material_id'],
    );
    final sourcePage = _integer(data['sourcePage'] ?? data['source_page']);
    final question = SubjectQuizQuestion(
      id: _text(data['id'] ?? data['question_id']),
      text: _text(data['prompt'] ?? data['text'] ?? data['question']),
      options: List<String>.unmodifiable(options),
      sourceMaterialId: sourceMaterialId,
      sourcePage: sourcePage,
      sourceLabel: _sourceLabel(sourceMaterialId, sourcePage),
    );
    question.validate();
    return question;
  }

  void validate() {
    if (id.isEmpty || text.isEmpty) {
      throw const FormatException('A quiz question was incomplete.');
    }
    if (options.length != 4) {
      throw const FormatException('A quiz question had invalid options.');
    }
    if (sourceMaterialId.isEmpty || sourcePage < 1) {
      throw const FormatException('A quiz question had an invalid source.');
    }
    if (options.any((option) => option.isEmpty) ||
        options.toSet().length != options.length) {
      throw const FormatException('Quiz options were empty or duplicated.');
    }
  }
}

class SubjectQuizAttempt {
  const SubjectQuizAttempt({
    required this.attemptId,
    required this.subjectId,
    required this.materialId,
    required this.questions,
    this.expiresAt,
  });

  final String attemptId;
  final String subjectId;
  final String materialId;
  final List<SubjectQuizQuestion> questions;
  final DateTime? expiresAt;

  factory SubjectQuizAttempt.fromMap(
    String requestedSubjectId,
    Map<Object?, Object?> data, {
    String? requestedMaterialId,
  }) {
    final rawQuestions = data['questions'];
    if (rawQuestions is! List) {
      throw const FormatException('The server did not return quiz questions.');
    }
    final responseMaterialId = _text(data['materialId'] ?? data['material_id']);
    final materialContext = responseMaterialId.isNotEmpty
        ? responseMaterialId
        : requestedMaterialId ?? '';
    final questions = rawQuestions
        .map((item) {
          if (item is! Map) {
            throw const FormatException(
              'A quiz question had an invalid format.',
            );
          }
          final questionMap = Map<Object?, Object?>.from(item);
          // The selected Material belongs to the quiz response, so the backend
          // does not need to repeat its UUID inside every question object.
          questionMap.putIfAbsent('source_material_id', () => materialContext);
          return SubjectQuizQuestion.fromMap(questionMap);
        })
        .toList(growable: false);
    if (questions.length != 10) {
      throw const FormatException(
        'A PeerStudy quiz must contain exactly 10 questions.',
      );
    }

    final materialId = responseMaterialId.isNotEmpty
        ? responseMaterialId
        : requestedMaterialId ?? questions.first.sourceMaterialId;
    final expiresAt = DateTime.tryParse(
      _text(data['expiresAt'] ?? data['expires_at']),
    );
    final attempt = SubjectQuizAttempt(
      attemptId: _text(
        data['attemptId'] ?? data['attempt_id'] ?? data['quiz_id'],
      ),
      subjectId: _text(
        data['subjectId'] ?? data['subject_id'],
        fallback: requestedSubjectId,
      ),
      materialId: materialId,
      questions: List<SubjectQuizQuestion>.unmodifiable(questions),
      expiresAt: expiresAt,
    );
    final allQuestionsUseSelectedMaterial = attempt.questions.every(
      (question) => question.sourceMaterialId == attempt.materialId,
    );
    if (attempt.attemptId.isEmpty ||
        attempt.subjectId != requestedSubjectId ||
        attempt.materialId.isEmpty ||
        (requestedMaterialId != null &&
            attempt.materialId != requestedMaterialId) ||
        !allQuestionsUseSelectedMaterial) {
      throw const FormatException('The quiz attempt context was invalid.');
    }
    return attempt;
  }
}

class QuizCorrection {
  const QuizCorrection({
    required this.questionId,
    required this.selectedIndex,
    required this.correctIndex,
    required this.explanation,
    required this.sourceLabel,
    this.questionText = '',
    this.selectedAnswer = '',
    this.correctAnswer = '',
  });

  final String questionId;
  final int selectedIndex;
  final int correctIndex;
  final String explanation;
  final String sourceLabel;
  final String questionText;
  final String selectedAnswer;
  final String correctAnswer;

  bool get isCorrect => selectedIndex == correctIndex;

  factory QuizCorrection.fromMap(Map<Object?, Object?> data) {
    final sourceMaterialId = _text(
      data['sourceMaterialId'] ?? data['source_material_id'],
    );
    final sourcePage = _integer(data['sourcePage'] ?? data['source_page']);
    return QuizCorrection(
      questionId: _text(data['questionId'] ?? data['question_id']),
      selectedIndex: _integer(
        data['selectedOption'] ??
            data['selected_option'] ??
            data['selected_index'],
        fallback: -1,
      ),
      correctIndex: _integer(
        data['correctOption'] ??
            data['correct_option'] ??
            data['correct_index'],
        fallback: -1,
      ),
      explanation: _text(data['explanation']),
      sourceLabel: _sourceLabel(sourceMaterialId, sourcePage),
      questionText: _text(data['prompt'] ?? data['question']),
      selectedAnswer: _text(data['selectedAnswer'] ?? data['selected_answer']),
      correctAnswer: _text(data['correctAnswer'] ?? data['correct_answer']),
    );
  }
}

class SubjectQuizResult {
  const SubjectQuizResult({
    required this.score,
    required this.total,
    required this.corrections,
    required this.submittedAt,
    required this.wasAlreadySubmitted,
  });

  final int score;
  final int total;
  final List<QuizCorrection> corrections;
  final DateTime submittedAt;
  final bool wasAlreadySubmitted;

  factory SubjectQuizResult.fromMap(Map<Object?, Object?> data) {
    final rawCorrections = data['corrections'] ?? data['feedback'];
    final corrections = rawCorrections is List
        ? rawCorrections
              .map((item) {
                if (item is! Map) {
                  throw const FormatException(
                    'The quiz correction format was invalid.',
                  );
                }
                return QuizCorrection.fromMap(Map<Object?, Object?>.from(item));
              })
              .toList(growable: false)
        : const <QuizCorrection>[];
    final submittedAt = DateTime.tryParse(
      _text(data['submittedAt'] ?? data['submitted_at']),
    );
    final result = SubjectQuizResult(
      score: _integer(data['score']),
      total: _integer(data['total'], fallback: 10),
      corrections: List<QuizCorrection>.unmodifiable(corrections),
      submittedAt: submittedAt ?? DateTime.now(),
      wasAlreadySubmitted:
          data['alreadySubmitted'] == true || data['already_submitted'] == true,
    );
    if (result.total != 10 ||
        result.corrections.length != 10 ||
        result.score < 0 ||
        result.score > result.total ||
        result.corrections.any(
          (item) =>
              item.questionId.isEmpty ||
              item.selectedIndex < 0 ||
              item.selectedIndex > 3 ||
              item.correctIndex < 0 ||
              item.correctIndex > 3,
        )) {
      throw const FormatException('The server returned invalid quiz feedback.');
    }
    return result;
  }
}

String _sourceLabel(String materialId, int page) {
  if (materialId.isEmpty) return 'Approved material';
  return page > 0 ? '$materialId - page $page' : materialId;
}

String _text(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _integer(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
