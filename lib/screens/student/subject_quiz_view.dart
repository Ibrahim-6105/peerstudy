// Student UI for one selected approved Material's ten-question practice quiz.

import 'package:flutter/material.dart';
import 'package:peerstudy/components/error_view.dart';
import 'package:peerstudy/components/loading_view.dart';
import 'package:peerstudy/models/quiz.dart';
import 'package:peerstudy/models/subject.dart';
import 'package:peerstudy/providers/quiz_provider.dart';
import 'package:peerstudy/providers/subject_provider.dart';
import 'package:peerstudy/theme/app_theme.dart';

class SubjectQuizView extends StatefulWidget {
  const SubjectQuizView({
    super.key,
    required this.subject,
    required this.controller,
  });

  final StudySubject subject;
  final SubjectQuizController controller;

  @override
  State<SubjectQuizView> createState() => _SubjectQuizViewState();
}

// This State object directly loads the approved PDFs used for quiz generation.
class _SubjectQuizViewState extends State<SubjectQuizView> {
  final SubjectRepository _repository = SubjectRepository();
  List<StudyMaterial> _materials = const <StudyMaterial>[];
  bool _isLoadingMaterials = true;
  bool _materialsFailed = false;

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  // A normal async method and setState keep this code easy to follow.
  Future<void> _loadMaterials() async {
    setState(() {
      _isLoadingMaterials = true;
      _materialsFailed = false;
    });
    try {
      final materials = await _repository.fetchMaterials(widget.subject);
      if (!mounted) return;
      setState(() {
        _materials = materials;
        _isLoadingMaterials = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _materials = const <StudyMaterial>[];
        _isLoadingMaterials = false;
        _materialsFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: switch (state.status) {
            QuizLoadStatus.choosingMaterial => _MaterialSelectionView(
              subject: widget.subject,
              state: state,
              controller: widget.controller,
              materials: _materials,
              isLoading: _isLoadingMaterials,
              hasError: _materialsFailed,
              onRetry: _loadMaterials,
            ),
            QuizLoadStatus.loading => const LoadingView(
              message: 'Generating exactly 10 questions from your Material...',
            ),
            QuizLoadStatus.error => _QuizGenerationError(
              message: state.errorMessage ?? 'The quiz is unavailable.',
              onRetry: widget.controller.retry,
              onChooseMaterial: widget.controller.chooseAnotherQuiz,
            ),
            QuizLoadStatus.completed => _QuizResultView(
              result: state.result!,
              onNewQuiz: widget.controller.chooseAnotherQuiz,
            ),
            QuizLoadStatus.ready || QuizLoadStatus.submitting => _QuestionView(
              state: state,
              controller: widget.controller,
            ),
          },
        ),
      ),
    );
  }
}

// The corrected flow begins here instead of spending an AI request on tab open.
class _MaterialSelectionView extends StatelessWidget {
  const _MaterialSelectionView({
    required this.subject,
    required this.state,
    required this.controller,
    required this.materials,
    required this.isLoading,
    required this.hasError,
    required this.onRetry,
  });

  final StudySubject subject;
  final QuizState state;
  final SubjectQuizController controller;
  final List<StudyMaterial> materials;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const LoadingView(
        message: 'Loading approved Materials for this Subject...',
      );
    }
    if (hasError) {
      return ErrorView(
        message: 'Approved Materials are unavailable. Please try again.',
        onRetry: onRetry,
      );
    }
    if (materials.isEmpty) {
      return _QuizMessage(
        icon: Icons.picture_as_pdf_outlined,
        title: 'No approved Material is available',
        message:
            'A quiz can start only after an approved PDF is published for '
            'this Subject.',
        buttonLabel: 'Check again',
        onPressed: onRetry,
      );
    }
    return ListView(
      padding: AppTheme.pagePadding,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Choose one approved Material',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${subject.name}: PeerStudy will generate exactly 10 practice '
          'questions from only the PDF you select.',
        ),
        const SizedBox(height: 10),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'This is supplementary practice, not an official assessment. '
              'Generation starts only after you press Start Quiz.',
            ),
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: state.selectedMaterialId,
          onChanged: (value) {
            if (value != null) controller.selectMaterial(value);
          },
          child: Column(
            children: [
              for (final material in materials)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: RadioListTile<String>(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    value: material.id,
                    title: Text(material.title),
                    subtitle: Text(
                      material.summary.trim().isEmpty
                          ? 'Approved PDF'
                          : material.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            state.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: FilledButton.icon(
            key: const ValueKey('start-approved-material-quiz'),
            onPressed: state.selectedMaterialId == null
                ? null
                : controller.start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start Quiz'),
          ),
        ),
      ],
    );
  }
}

class _QuizGenerationError extends StatelessWidget {
  const _QuizGenerationError({
    required this.message,
    required this.onRetry,
    required this.onChooseMaterial,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onChooseMaterial;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppTheme.pagePadding,
      children: [
        ErrorView(message: message, onRetry: onRetry),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onChooseMaterial,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Choose a different Material'),
        ),
      ],
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({required this.state, required this.controller});

  final QuizState state;
  final SubjectQuizController controller;

  @override
  Widget build(BuildContext context) {
    final attempt = state.attempt!;
    final index = state.currentQuestionIndex;
    final question = attempt.questions[index];
    final selected = state.answers[index];
    final isSubmitting = state.status == QuizLoadStatus.submitting;

    return ListView(
      padding: AppTheme.pagePadding,
      children: [
        Semantics(
          liveRegion: true,
          label: 'Question ${index + 1} of 10',
          child: LinearProgressIndicator(value: (index + 1) / 10),
        ),
        const SizedBox(height: 12),
        Text(
          'Question ${index + 1} of 10',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Selected Material: ${attempt.materialId}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  question.text,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Source: ${question.sourceLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                RadioGroup<int>(
                  groupValue: selected,
                  onChanged: (value) {
                    if (!isSubmitting && value != null) {
                      controller.selectAnswer(index, value);
                    }
                  },
                  child: Column(
                    children: [
                      for (
                        var optionIndex = 0;
                        optionIndex < question.options.length;
                        optionIndex++
                      )
                        RadioListTile<int>(
                          value: optionIndex,
                          enabled: !isSubmitting,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(question.options[optionIndex]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            state.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isSubmitting || index == 0
                    ? null
                    : () => controller.showQuestion(index - 1),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Previous'),
              ),
            ),
            const SizedBox(width: 10),
            if (index < 9)
              Expanded(
                child: FilledButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () => controller.showQuestion(index + 1),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Next'),
                ),
              )
            else
              Expanded(
                child: FilledButton.icon(
                  onPressed: isSubmitting ? null : controller.submit,
                  icon: isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined),
                  label: Text(isSubmitting ? 'Scoring...' : 'Submit'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _QuizResultView extends StatelessWidget {
  const _QuizResultView({required this.result, required this.onNewQuiz});

  final SubjectQuizResult result;
  final VoidCallback onNewQuiz;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppTheme.pagePadding,
      children: [
        Semantics(
          liveRegion: true,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 36,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${result.score} / ${result.total}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text('Saved practice score'),
                  if (result.wasAlreadySubmitted)
                    const Text('This saved result was returned safely again.'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Correction feedback',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < result.corrections.length; index++) ...[
          _CorrectionCard(
            number: index + 1,
            correction: result.corrections[index],
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: onNewQuiz,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Choose Material for another quiz'),
        ),
      ],
    );
  }
}

class _CorrectionCard extends StatelessWidget {
  const _CorrectionCard({required this.number, required this.correction});

  final int number;
  final QuizCorrection correction;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (correction.selectedAnswer.isNotEmpty)
        'Your answer: ${correction.selectedAnswer}',
      if (correction.correctAnswer.isNotEmpty)
        'Correct answer: ${correction.correctAnswer}',
      correction.explanation,
      'Source: ${correction.sourceLabel}',
    ].where((item) => item.trim().isNotEmpty).join('\n');
    return Card(
      child: ListTile(
        minTileHeight: 60,
        dense: true,
        leading: Icon(
          correction.isCorrect
              ? Icons.check_circle_outline
              : Icons.error_outline,
          // Theme colors keep this status icon readable in light and dark mode.
          color: correction.isCorrect
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
        title: Text(
          'Question $number - ${correction.isCorrect ? 'Correct' : 'Review'}',
        ),
        subtitle: Text(details),
        isThreeLine: true,
      ),
    );
  }
}

class _QuizMessage extends StatelessWidget {
  const _QuizMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppTheme.pagePadding,
      children: [
        const SizedBox(height: 32),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(icon, size: 34),
                const SizedBox(height: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(buttonLabel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
