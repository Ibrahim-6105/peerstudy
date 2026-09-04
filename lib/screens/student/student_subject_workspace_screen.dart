// One subject-scoped workspace with the three areas required by the final FYP.
//
// Official Materials, AI Quiz, and Community all stay bound to one subject ID.

// Material supplies the page shell, tabs, cards, icons, and state widgets.
import 'package:flutter/material.dart';

// Typed subject and material models keep this workspace subject-scoped.
import 'package:peerstudy/models/subject.dart';

// Quiz state lets the workspace confirm before discarding unfinished answers.
import 'package:peerstudy/providers/quiz_provider.dart';

// SubjectRepository supplies the approved PDF catalog.
import 'package:peerstudy/providers/subject_provider.dart';

// The protected opener requests temporary access for the phone's PDF viewer.
import 'package:peerstudy/screens/student/material_viewer_screen.dart';
import 'package:peerstudy/screens/student/subject_community_views.dart';
import 'package:peerstudy/screens/student/subject_quiz_view.dart';

// Shared page spacing and readable-width limits are reused here.
import 'package:peerstudy/theme/app_theme.dart';

// StudentSubjectWorkspaceScreen keeps all tools tied to one StudySubject id.
class StudentSubjectWorkspaceScreen extends StatefulWidget {
  const StudentSubjectWorkspaceScreen({required this.subject, super.key});

  // The complete object gives every tab the same trusted subject identifier.
  final StudySubject subject;

  @override
  State<StudentSubjectWorkspaceScreen> createState() =>
      _StudentSubjectWorkspaceScreenState();
}

class _StudentSubjectWorkspaceScreenState
    extends State<StudentSubjectWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final SubjectQuizController _quizController;
  int _acceptedTabIndex = 0;
  bool _isChoosingTab = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // The simple controller asks this widget to rebuild through setState.
    _quizController = SubjectQuizController(
      subjectId: widget.subject.id,
      onChanged: (newState) {
        // Ignore a late network response after this page has been closed.
        if (!mounted) return;
        setState(() {});
      },
    );
  }

  @override
  void dispose() {
    // Ignore any generation or scoring response that finishes after closing.
    _quizController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    final hasIncompleteQuiz = _quizController.state.hasIncompleteQuiz;
    return PopScope(
      canPop: !hasIncompleteQuiz,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !hasIncompleteQuiz) return;
        final leave = await _confirmLeaveIncompleteQuiz();
        if (!leave || !context.mounted) return;
        _quizController.abandonIncompleteQuiz();
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          // The explicit back button has a useful desktop accessibility tooltip.
          leading: IconButton(
            tooltip: 'Back to active subjects',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(subject.name),
          // Text-only tabs keep the workspace compact on narrow phones.
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            onTap: _requestTab,
            tabs: const [
              Tooltip(
                message: 'Show official materials',
                child: Tab(text: 'Materials'),
              ),
              Tooltip(
                message: 'Show AI quiz',
                child: Tab(text: 'AI Quiz'),
              ),
              Tooltip(
                message: 'Show subject Community',
                child: Tab(text: 'Community'),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          // Each child is a separate, swipeable workspace destination.
          child: TabBarView(
            controller: _tabController,
            // Swipe is disabled so every quiz exit asks for confirmation.
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _OfficialMaterialsTab(subject: subject),
              SubjectQuizView(subject: subject, controller: _quizController),
              SubjectCommunityView(subject: subject),
            ],
          ),
        ),
      ),
    );
  }

  // TabBar changes first, so return to the accepted tab while asking whether
  // the unfinished answers may be discarded.
  Future<void> _requestTab(int requestedIndex) async {
    if (_isChoosingTab || requestedIndex == _acceptedTabIndex) return;
    final leavingIncompleteQuiz =
        _acceptedTabIndex == 1 &&
        requestedIndex != 1 &&
        _quizController.state.hasIncompleteQuiz;
    if (!leavingIncompleteQuiz) {
      _acceptedTabIndex = requestedIndex;
      return;
    }

    _isChoosingTab = true;
    _tabController.animateTo(_acceptedTabIndex);
    final leave = await _confirmLeaveIncompleteQuiz();
    if (!mounted) return;
    if (leave) {
      _quizController.abandonIncompleteQuiz();
      _acceptedTabIndex = requestedIndex;
      _tabController.animateTo(requestedIndex);
    }
    _isChoosingTab = false;
  }

  Future<bool> _confirmLeaveIncompleteQuiz() async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave incomplete quiz?'),
        content: const Text(
          'Your selected answers have not been submitted. Leaving now will '
          'discard this unfinished practice attempt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continue quiz'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave quiz'),
          ),
        ],
      ),
    );
    return decision ?? false;
  }
}

// Connected tab that lists approved PDF metadata for the current subject.
class _OfficialMaterialsTab extends StatefulWidget {
  const _OfficialMaterialsTab({required this.subject});

  final StudySubject subject;

  @override
  State<_OfficialMaterialsTab> createState() => _OfficialMaterialsTabState();
}

// One repository, one list, and setState replace the old provider here.
class _OfficialMaterialsTabState extends State<_OfficialMaterialsTab> {
  final SubjectRepository _repository = SubjectRepository();
  List<StudyMaterial> _materials = const <StudyMaterial>[];
  bool _isLoading = true;
  Object? _error;

  StudySubject get subject => widget.subject;

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  // Fetch only approved PDF rows for the exact Subject supplied by the page.
  Future<void> _loadMaterials() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final materials = await _repository.fetchMaterials(subject);
      if (!mounted) return;
      setState(() {
        _materials = materials;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _materials = const <StudyMaterial>[];
        _isLoading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_isLoading) {
      content = const _MaterialLoadingState();
    } else if (_error != null) {
      content = _MaterialErrorState(error: _error!, onRetry: _loadMaterials);
    } else if (_materials.isEmpty) {
      content = _MaterialEmptyState(onRetry: _loadMaterials);
    } else {
      content = RefreshIndicator(
        onRefresh: _loadMaterials,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppTheme.pagePadding,
          children: [
            _WorkspaceHeading(
              title: 'Official Materials',
              subject: subject,
              description: 'Approved lecture PDF records for this subject.',
            ),
            const SizedBox(height: 8),
            const _MaterialAccessNotice(),
            const SizedBox(height: 8),
            for (final material in _materials) ...[
              _MaterialCard(
                material: material,
                onOpen: () {
                  MaterialViewerScreen.open(context, material: material);
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
    }

    // ConstrainedBox prevents long metadata rows stretching across wide screens.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTheme.contentWidth),
        // Loading, empty, error, and data are all intentional visible states.
        child: content,
      ),
    );
  }
}

// Reusable heading shown at the start of each subject tool.
class _WorkspaceHeading extends StatelessWidget {
  const _WorkspaceHeading({
    required this.title,
    required this.subject,
    required this.description,
  });

  final String title;
  final StudySubject subject;
  final String description;

  @override
  Widget build(BuildContext context) {
    // The optional subject code is real metadata and is never substituted.
    final code = subject.code.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 5),
        Text(
          code.isEmpty ? subject.name : '$code - ${subject.name}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 5),
        Text(description),
      ],
    );
  }
}

// Explains temporary access through the device's reliable PDF application.
class _MaterialAccessNotice extends StatelessWidget {
  const _MaterialAccessNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Tap an approved PDF to open it securely with temporary access.',
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Tap an approved PDF to open it securely in your PDF app or '
                  'browser. The access link is temporary.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// One interactive approved material record from Supabase.
class _MaterialCard extends StatelessWidget {
  const _MaterialCard({required this.material, required this.onOpen});

  final StudyMaterial material;

  // The parent opens this exact material through a temporary protected link.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    // Small metadata strings are calculated before composing screen-reader text.
    final sizeLabel = _formatBytes(material.sizeBytes);
    final dateLabel = _formatDate(material.updatedAt);

    // Only useful public metadata is shown; the internal revision stays hidden.
    final details = <String>[
      if (sizeLabel.isNotEmpty) sizeLabel,
      if (dateLabel.isNotEmpty) 'Updated $dateLabel',
    ].join(' - ');
    final semanticDetails = <String>[
      material.title,
      'Approved PDF',
      if (details.isNotEmpty) details,
    ].join('. ');

    return Tooltip(
      message: 'Open ${material.title}',
      child: Semantics(
        button: true,
        label: '$semanticDetails.',
        hint: 'Opens the secure PDF in your PDF app or browser',
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 76),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.errorContainer,
                        child: Icon(
                          Icons.picture_as_pdf_rounded,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            material.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 5),
                          const Text('Approved PDF'),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(details),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const ExcludeSemantics(
                      child: Icon(Icons.chevron_right_rounded, size: 24),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Loading state for the first material stream result.
class _MaterialLoadingState extends StatelessWidget {
  const _MaterialLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Loading official materials',
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 10),
              Text('Loading official materials...'),
            ],
          ),
        ),
      ),
    );
  }
}

// Empty materials state after a successful approved-record query.
class _MaterialEmptyState extends StatelessWidget {
  const _MaterialEmptyState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _MaterialMessageList(
      icon: Icons.picture_as_pdf_outlined,
      title: 'No official materials yet',
      message:
          'No approved PDF materials have been published for this subject. '
          'Please check again later.',
      buttonLabel: 'Check again',
      onPressed: onRetry,
    );
  }
}

// Material errors show an offline-specific message only when evidence suggests it.
class _MaterialErrorState extends StatelessWidget {
  const _MaterialErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // No connectivity plugin is present, so the wording remains "may be".
    final isLikelyOffline = _looksLikeOfflineError(error);

    return _MaterialMessageList(
      icon: isLikelyOffline ? Icons.cloud_off_outlined : Icons.error_outline,
      title: isLikelyOffline
          ? 'You may be offline'
          : 'Official materials did not load',
      message: isLikelyOffline
          ? 'Check your internet connection, then try again.'
          : 'Approved material records are unavailable right now. No local '
                'record has been changed.',
      buttonLabel: 'Try again',
      onPressed: onRetry,
    );
  }
}

// Shared scrollable layout used by material empty and error states.
class _MaterialMessageList extends StatelessWidget {
  const _MaterialMessageList({
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
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppTheme.pagePadding,
      children: [
        const SizedBox(height: 36),
        Semantics(
          liveRegion: true,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ExcludeSemantics(child: Icon(icon, size: 34)),
                  const SizedBox(height: 10),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 5),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Tooltip(
                    message: buttonLabel,
                    child: SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: onPressed,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(buttonLabel),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Converts bytes into a short student-friendly size without another package.
String _formatBytes(int bytes) {
  // Zero or negative values mean size metadata was not supplied.
  if (bytes <= 0) return '';

  // Small files remain exact because a decimal unit would add no value.
  if (bytes < 1024) return '$bytes B';

  // Values below one mebibyte are displayed as kibibytes with one decimal.
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  // Larger lecture files are easiest to understand as mebibytes.
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// Formats a database date without adding a date-formatting dependency.
String _formatDate(DateTime date) {
  // The model uses 1970 when Supabase has no valid update timestamp.
  if (date.year <= 1970) return '';

  // padLeft keeps month and day consistently two digits long.
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

// Conservative text matching provides a useful offline hint without claiming
// certainty when the current dependencies cannot measure connectivity directly.
bool _looksLikeOfflineError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('unavailable') ||
      message.contains('network') ||
      message.contains('offline') ||
      message.contains('connection');
}
