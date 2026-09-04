// Simple quiz controller used by a StatefulWidget and setState.
//
// Beginner note:
// This is a normal Dart class. It is not Riverpod, Provider, Bloc, or another
// state-management system. SubjectQuizView gives it an onChanged function, and
// the controller calls that function after its plain QuizState value changes.

// Typed quiz models validate every response returned by the backend function.
import 'package:peerstudy/models/quiz.dart';

// BackendApiService sends authenticated generation and scoring requests.
import 'package:peerstudy/services/backend_api_service.dart';

// UUID values make retries safe without creating duplicate attempts or scores.
import 'package:uuid/uuid.dart';

// Tests can replace the real generation request with one small callback.
typedef QuizGenerationCall =
    Future<Map<Object?, Object?>> Function({
      required String subjectId,
      required String materialId,
      required String idempotencyKey,
    });

// Tests can replace the real scoring request with one small callback.
typedef QuizSubmissionCall =
    Future<Map<Object?, Object?>> Function({
      required String quizId,
      required List<int> answers,
      required String idempotencyKey,
    });

// The widget uses this callback to call setState after a controller change.
typedef QuizStateChanged = void Function(QuizState newState);

// These values describe the one visible step of the quiz flow.
enum QuizLoadStatus {
  choosingMaterial,
  loading,
  ready,
  submitting,
  completed,
  error,
}

// QuizState is one easy-to-read snapshot of the current quiz screen.
class QuizState {
  const QuizState({
    this.status = QuizLoadStatus.choosingMaterial,
    this.selectedMaterialId,
    this.attempt,
    this.answers = const <int, int>{},
    this.currentQuestionIndex = 0,
    this.result,
    this.errorMessage,
  });

  // The current screen section, such as choosing, answering, or completed.
  final QuizLoadStatus status;

  // The approved PDF selected by the student before generation begins.
  final String? selectedMaterialId;

  // The ten generated questions returned by the protected backend.
  final SubjectQuizAttempt? attempt;

  // Each map key is a question index and each value is an option index.
  final Map<int, int> answers;

  // The question currently displayed in the simple previous/next interface.
  final int currentQuestionIndex;

  // The saved score and corrections returned after a successful submission.
  final SubjectQuizResult? result;

  // Safe student-facing text for a retryable problem.
  final String? errorMessage;

  // A generated but unsubmitted attempt must be confirmed before discarding.
  bool get hasIncompleteQuiz =>
      attempt != null &&
      result == null &&
      (status == QuizLoadStatus.ready || status == QuizLoadStatus.submitting);

  // copyWith changes only the named values and keeps every other value.
  QuizState copyWith({
    QuizLoadStatus? status,
    String? selectedMaterialId,
    SubjectQuizAttempt? attempt,
    Map<int, int>? answers,
    int? currentQuestionIndex,
    SubjectQuizResult? result,
    String? errorMessage,
    bool clearAttempt = false,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return QuizState(
      status: status ?? this.status,
      selectedMaterialId: selectedMaterialId ?? this.selectedMaterialId,
      attempt: clearAttempt ? null : attempt ?? this.attempt,
      answers: Map<int, int>.unmodifiable(answers ?? this.answers),
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      result: clearResult ? null : result ?? this.result,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

// SubjectQuizController contains the small amount of quiz business logic.
class SubjectQuizController {
  SubjectQuizController({
    required this.subjectId,
    this.onChanged,
    BackendApiService? backend,
    this.generationCall,
    this.submissionCall,
  }) : _providedBackend = backend;

  // Every generated attempt is restricted to this active Subject UUID.
  final String subjectId;

  // The StatefulWidget supplies this and normally calls setState inside it.
  final QuizStateChanged? onChanged;

  // A supplied backend keeps focused tests independent from app startup.
  final BackendApiService? _providedBackend;

  // Optional test callbacks avoid making live network requests in unit tests.
  final QuizGenerationCall? generationCall;
  final QuizSubmissionCall? submissionCall;

  // Production creates the backend helper only when it is first needed.
  BackendApiService? _createdBackend;

  // The current state is a normal public read-only property.
  QuizState state = const QuizState();

  // UUID has no widget state and can be safely shared by every controller.
  static const Uuid _uuid = Uuid();

  // Keys survive retries so a slow response cannot create a duplicate request.
  String? _generationKey;
  String? _submissionKey;

  // A rapid double tap must not spend two provider requests before the first
  // idempotent result has had a chance to reach the database.
  bool _generationInFlight = false;

  // This becomes true when the Subject workspace has been closed.
  bool _isDisposed = false;

  // Use the injected helper in tests or lazily create the real app helper.
  BackendApiService get _backend {
    return _providedBackend ?? (_createdBackend ??= BackendApiService());
  }

  // Change the value and tell the owner widget to run setState.
  void _change(QuizState newState) {
    // A network response may finish after the user already left the workspace.
    if (_isDisposed) return;
    state = newState;
    onChanged?.call(newState);
  }

  // Stop all future UI notifications when the owner widget is removed.
  void dispose() {
    _isDisposed = true;
  }

  // Selection alone does not spend an AI request.
  void selectMaterial(String materialId) {
    final cleanMaterialId = materialId.trim();
    if (cleanMaterialId.isEmpty || state.status == QuizLoadStatus.loading) {
      return;
    }
    if (state.hasIncompleteQuiz || state.status == QuizLoadStatus.submitting) {
      return;
    }
    if (cleanMaterialId != state.selectedMaterialId) {
      _generationKey = null;
    }
    _change(QuizState(selectedMaterialId: cleanMaterialId));
  }

  // Generate exactly one protected quiz from the selected approved PDF.
  Future<void> start() async {
    final materialId = state.selectedMaterialId?.trim() ?? '';
    if (materialId.isEmpty) {
      _change(
        state.copyWith(
          errorMessage:
              'Choose one approved Material before starting the quiz.',
        ),
      );
      return;
    }
    if (_generationInFlight || _isDisposed) return;

    _generationInFlight = true;
    _submissionKey = null;
    final idempotencyKey = _generationKey ??= _uuid.v4();
    _change(
      QuizState(status: QuizLoadStatus.loading, selectedMaterialId: materialId),
    );

    try {
      final generate = generationCall;
      final data = generate != null
          ? await generate(
              subjectId: subjectId,
              materialId: materialId,
              idempotencyKey: idempotencyKey,
            )
          : await _backend.generateQuiz(
              subjectId,
              materialId: materialId,
              idempotencyKey: idempotencyKey,
            );
      final attempt = SubjectQuizAttempt.fromMap(
        subjectId,
        data,
        requestedMaterialId: materialId,
      );
      _change(
        QuizState(
          status: QuizLoadStatus.ready,
          selectedMaterialId: materialId,
          attempt: attempt,
        ),
      );
    } catch (error) {
      _change(
        QuizState(
          status: QuizLoadStatus.error,
          selectedMaterialId: materialId,
          errorMessage:
              '${_friendlyError(error)} Retry safely to recover the same request.',
        ),
      );
    } finally {
      _generationInFlight = false;
    }
  }

  // Retry generation with the same safe key and the same selected material.
  Future<void> retry() => start();

  // Return to material selection only when the student asks for another quiz.
  void chooseAnotherQuiz() {
    _generationKey = null;
    _submissionKey = null;
    _change(const QuizState());
  }

  // Discard an incomplete attempt only after the UI confirms the choice.
  void abandonIncompleteQuiz() {
    if (!state.hasIncompleteQuiz) return;
    _generationKey = null;
    _submissionKey = null;
    _change(const QuizState());
  }

  // Save one selected option for one valid generated question.
  void selectAnswer(int questionIndex, int optionIndex) {
    if (state.status != QuizLoadStatus.ready) return;
    final attempt = state.attempt;
    if (attempt == null ||
        questionIndex < 0 ||
        questionIndex >= attempt.questions.length ||
        optionIndex < 0 ||
        optionIndex >= attempt.questions[questionIndex].options.length) {
      return;
    }
    _change(
      state.copyWith(
        answers: <int, int>{...state.answers, questionIndex: optionIndex},
        clearError: true,
      ),
    );
  }

  // Move between the existing ten questions without changing any answers.
  void showQuestion(int index) {
    final count = state.attempt?.questions.length ?? 0;
    if (index < 0 || index >= count) return;
    _change(state.copyWith(currentQuestionIndex: index));
  }

  // Send all ten ordered answers and store the server-calculated result.
  Future<void> submit() async {
    final attempt = state.attempt;
    if (state.status != QuizLoadStatus.ready || attempt == null) return;
    if (state.answers.length != 10) {
      _change(
        state.copyWith(
          errorMessage: 'Answer all 10 questions before submitting.',
        ),
      );
      return;
    }

    _change(
      state.copyWith(status: QuizLoadStatus.submitting, clearError: true),
    );
    final orderedAnswers = List<int>.generate(
      10,
      (index) => state.answers[index]!,
    );
    final idempotencyKey = _submissionKey ??= _uuid.v4();

    try {
      final submitAnswers = submissionCall;
      final data = submitAnswers != null
          ? await submitAnswers(
              quizId: attempt.attemptId,
              answers: orderedAnswers,
              idempotencyKey: idempotencyKey,
            )
          : await _backend.submitQuiz(
              quizId: attempt.attemptId,
              answers: orderedAnswers,
              idempotencyKey: idempotencyKey,
            );
      final result = SubjectQuizResult.fromMap(data);
      _change(
        state.copyWith(
          status: QuizLoadStatus.completed,
          result: result,
          clearError: true,
        ),
      );
    } catch (error) {
      _change(
        state.copyWith(
          status: QuizLoadStatus.ready,
          errorMessage: '${_friendlyError(error)} Your answers are still here.',
        ),
      );
    }
  }
}

// Remove exception prefixes while keeping safe messages readable for students.
String _friendlyError(Object error) {
  final text = error.toString().trim();
  final separator = text.indexOf(': ');
  return separator >= 0 ? text.substring(separator + 2) : text;
}
