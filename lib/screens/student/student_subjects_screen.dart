// Active-subject list for one department inside a supported academic area.
//
// This is a complete page because it is opened from the department tab. Every
// row comes from SubjectRepository, so unavailable or made-up subjects are
// never inserted by the interface.

// unawaited lets local recent-activity saving happen without delaying navigation.
import 'dart:async';

// Material supplies Scaffold, navigation, cards, icons, and text widgets.
import 'package:flutter/material.dart';

// Typed department and subject models make navigation arguments clear.
import 'package:peerstudy/models/subject.dart';

// The plain repository reads active subjects for the chosen department id.
import 'package:peerstudy/providers/subject_provider.dart';

// This simple singleton saves the last genuine academic path on the phone.
import 'package:peerstudy/providers/settings_provider.dart';

// Tapping a real subject opens its three-part workspace directly.
import 'package:peerstudy/screens/student/student_subject_workspace_screen.dart';

// Shared spacing and width values keep student screens visually consistent.
import 'package:peerstudy/theme/app_theme.dart';

// StudentSubjectsScreen owns one department's visible subject list.
class StudentSubjectsScreen extends StatefulWidget {
  const StudentSubjectsScreen({
    required this.area,
    required this.department,
    super.key,
  });

  // The parent passes the complete validated hierarchy instead of loose text.
  final AcademicArea area;
  final AcademicDepartment department;

  @override
  State<StudentSubjectsScreen> createState() => _StudentSubjectsScreenState();
}

// One normal State object owns one live Subject list.
class _StudentSubjectsScreenState extends State<StudentSubjectsScreen> {
  // SubjectRepository keeps Supabase code outside the visual widgets below.
  final SubjectRepository _repository = SubjectRepository();

  // These three fields describe loading, data, and error without a package.
  List<StudySubject> _subjects = const <StudySubject>[];
  bool _isLoading = true;
  Object? _error;

  // Short getters keep the widget code readable for a beginner.
  AcademicArea get area => widget.area;
  AcademicDepartment get department => widget.department;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  // Fetch active Subjects and update the screen with ordinary setState.
  Future<void> _loadSubjects() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final subjects = await _repository.fetchSubjects(department);
      if (!mounted) return;
      setState(() {
        _subjects = subjects;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _subjects = const <StudySubject>[];
        _isLoading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Select the visible body with simple if statements.
    Widget content;
    if (_isLoading) {
      content = const _SubjectLoadingState();
    } else if (_error != null) {
      content = _SubjectErrorState(error: _error!, onRetry: _loadSubjects);
    } else if (_subjects.isEmpty) {
      content = _SubjectEmptyState(onRetry: _loadSubjects);
    } else {
      content = RefreshIndicator(
        onRefresh: _loadSubjects,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppTheme.pagePadding,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Active subjects',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '$peerStudySchoolName -> ${_academicAreaLabel(area)} '
              '-> ${department.name}. Only active subjects are shown.',
            ),
            const SizedBox(height: 14),
            for (final subject in _subjects) ...[
              _SubjectCard(
                subject: subject,
                onOpen: () {
                  // Remember only a subject that came from the live catalog.
                  StudentSelectionStore.instance.chooseSubject(
                    area: area,
                    department: department,
                    subject: subject,
                  );
                  // Save recent activity locally, but never block the workspace.
                  unawaited(
                    SettingsNotifier.instance.rememberSelection(
                      areaId: area.id,
                      departmentId: department.id,
                      subjectId: subject.id,
                    ),
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          StudentSubjectWorkspaceScreen(subject: subject),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        // An explicit tooltip makes the back icon understandable on desktop.
        leading: IconButton(
          tooltip: 'Back to departments',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(department.name),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTheme.contentWidth),
            // Loading, empty, error, and data are all visible and retryable.
            child: content,
          ),
        ),
      ),
    );
  }
}

// A subject tile shows only fields that exist on the real StudySubject model.
class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.subject, required this.onOpen});

  // Subject includes the stable id later used to scope the whole workspace.
  final StudySubject subject;

  // Navigation remains in the parent so this view is easy to understand.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    // Optional fields are normalized once before building several widgets.
    final code = subject.code.trim();
    final description = subject.description.trim();

    return Tooltip(
      message: 'Open ${subject.name}',
      child: Semantics(
        button: true,
        label: 'Open subject ${subject.name}',
        hint: 'Opens the subject workspace',
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            // A compact row still stays above Flutter's minimum tap target.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 76),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ExcludeSemantics(
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: Icon(
                          Icons.menu_book_rounded,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Code is not displayed when the database left it blank.
                          if (code.isNotEmpty) ...[
                            Text(
                              code,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: 3),
                          ],
                          Text(
                            subject.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          // Description is also optional and never fabricated.
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
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

// Loading remains visible until the filtered Supabase request finishes.
class _SubjectLoadingState extends StatelessWidget {
  const _SubjectLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Loading active subjects',
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
              Text('Loading active subjects…'),
            ],
          ),
        ),
      ),
    );
  }
}

// A completed query can honestly contain no published active subjects.
class _SubjectEmptyState extends StatelessWidget {
  const _SubjectEmptyState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _SubjectMessageList(
      icon: Icons.menu_book_outlined,
      title: 'No active subjects yet',
      message:
          'This department has no active subjects available right now. '
          'Please check again later.',
      buttonLabel: 'Check again',
      onPressed: onRetry,
    );
  }
}

// Failed reads receive a safe message instead of raw database details.
class _SubjectErrorState extends StatelessWidget {
  const _SubjectErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // The app has no connectivity package, so this is intentionally cautious.
    final isLikelyOffline = _looksLikeOfflineError(error);

    return _SubjectMessageList(
      icon: isLikelyOffline ? Icons.cloud_off_outlined : Icons.error_outline,
      title: isLikelyOffline ? 'You may be offline' : 'Subjects did not load',
      message: isLikelyOffline
          ? 'Check your internet connection, then try again.'
          : 'The active subject list is unavailable right now. Please try '
                'again in a moment.',
      buttonLabel: 'Try again',
      onPressed: onRetry,
    );
  }
}

// Shared state card reduces repeated empty/error layout code in this file.
class _SubjectMessageList extends StatelessWidget {
  const _SubjectMessageList({
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

// Uses the exact top-level names required by the revised report.
String _academicAreaLabel(AcademicArea area) {
  return area.displayName;
}

// Conservative matching avoids calling every unknown server error "offline".
bool _looksLikeOfflineError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('unavailable') ||
      message.contains('network') ||
      message.contains('offline') ||
      message.contains('connection');
}
