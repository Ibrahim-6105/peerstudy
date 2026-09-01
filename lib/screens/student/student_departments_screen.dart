// Student catalog entry for School -> Academic Area -> Department -> Subject.
//
// Beginner note:
// The revised FYP adds one clear level before departments. This file keeps the
// area page and its small department page together so the folder stays simple.

import 'package:flutter/material.dart';
import 'package:peerstudy/models/subject.dart';
import 'package:peerstudy/providers/subject_provider.dart';
import 'package:peerstudy/screens/student/student_subjects_screen.dart';
import 'package:peerstudy/theme/app_theme.dart';

// This widget remains the shell's catalog tab, but now starts with areas.
class StudentDepartmentsScreen extends StatefulWidget {
  const StudentDepartmentsScreen({super.key});

  @override
  State<StudentDepartmentsScreen> createState() =>
      _StudentDepartmentsScreenState();
}

// A few plain fields and setState replace the former provider state.
class _StudentDepartmentsScreenState extends State<StudentDepartmentsScreen> {
  // The repository contains every Supabase query for the academic catalog.
  final SubjectRepository _repository = SubjectRepository();

  // The live list is empty until the request finishes successfully.
  List<AcademicArea> _areas = const <AcademicArea>[];

  // Loading and error are explicit so the phone never shows a frozen page.
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  // Areas require the real School id, so both requests remain correctly linked.
  Future<void> _loadAreas() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final school = await _repository.fetchSchool();
      final areas = await _repository.fetchAcademicAreas(school.id);
      if (!mounted) return;
      setState(() {
        _areas = areas;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _areas = const <AcademicArea>[];
        _isLoading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Choose one simple widget for the current request state.
    Widget content;
    if (_isLoading) {
      content = const _CatalogLoading(label: 'academic areas');
    } else if (_error != null) {
      content = _CatalogMessage(
        icon: _looksLikeOfflineError(_error!)
            ? Icons.cloud_off_outlined
            : Icons.error_outline,
        title: 'Academic areas did not load',
        message: 'The live catalog is unavailable. Reconnect and try again.',
        buttonLabel: 'Try again',
        onPressed: _loadAreas,
      );
    } else if (_areas.isEmpty) {
      content = _CatalogMessage(
        icon: Icons.account_tree_outlined,
        title: 'No academic areas are available',
        message: 'IT and ENGINEERING have not been activated in the catalog.',
        buttonLabel: 'Check again',
        onPressed: _loadAreas,
      );
    } else {
      content = RefreshIndicator(
        onRefresh: _loadAreas,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppTheme.pagePadding,
          children: [
            Semantics(
              header: true,
              child: Text(
                peerStudySchoolName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Choose Information Technology or Engineering, then choose '
              'one of its configured Departments and active Subjects.',
            ),
            const SizedBox(height: 14),
            for (final area in _areas) ...[
              _CatalogCard(
                icon: area.supportedCode == AcademicAreaCode.it
                    ? Icons.computer_rounded
                    : Icons.engineering_rounded,
                title: _academicAreaLabel(area),
                subtitle: 'View departments',
                onOpen: () {
                  StudentSelectionStore.instance.chooseArea(area);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          _StudentAreaDepartmentsScreen(area: area),
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

    // The catalog is a tab root, so it also protects itself when reused.
    return SafeArea(top: false, child: _CatalogFrame(child: content));
  }
}

// Lists departments that belong to one already selected academic area.
class _StudentAreaDepartmentsScreen extends StatefulWidget {
  const _StudentAreaDepartmentsScreen({required this.area});

  final AcademicArea area;

  @override
  State<_StudentAreaDepartmentsScreen> createState() =>
      _StudentAreaDepartmentsScreenState();
}

// This page uses the same beginner loading pattern for one Area's Departments.
class _StudentAreaDepartmentsScreenState
    extends State<_StudentAreaDepartmentsScreen> {
  final SubjectRepository _repository = SubjectRepository();
  List<AcademicDepartment> _departments = const <AcademicDepartment>[];
  bool _isLoading = true;
  Object? _error;

  AcademicArea get area => widget.area;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final departments = await _repository.fetchDepartments(area.id);
      if (!mounted) return;
      setState(() {
        _departments = departments;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _departments = const <AcademicDepartment>[];
        _isLoading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_isLoading) {
      content = const _CatalogLoading(label: 'departments');
    } else if (_error != null) {
      content = _CatalogMessage(
        icon: _looksLikeOfflineError(_error!)
            ? Icons.cloud_off_outlined
            : Icons.error_outline,
        title: 'Departments did not load',
        message: 'The active department list is unavailable. Try again.',
        buttonLabel: 'Try again',
        onPressed: _loadDepartments,
      );
    } else if (_departments.isEmpty) {
      content = _CatalogMessage(
        icon: Icons.school_outlined,
        title: 'No active departments',
        message:
            '${_academicAreaLabel(area)} has no active departments right now.',
        buttonLabel: 'Check again',
        onPressed: _loadDepartments,
      );
    } else {
      content = RefreshIndicator(
        onRefresh: _loadDepartments,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppTheme.pagePadding,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Choose a department',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '$peerStudySchoolName -> ${_academicAreaLabel(area)}. '
              'Only its configured active Departments are shown.',
            ),
            const SizedBox(height: 14),
            for (final department in _departments) ...[
              _CatalogCard(
                icon: Icons.account_balance_outlined,
                title: department.name,
                subtitle: 'View active subjects',
                onOpen: () {
                  StudentSelectionStore.instance.chooseDepartment(
                    area: area,
                    department: department,
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => StudentSubjectsScreen(
                        area: area,
                        department: department,
                      ),
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
        leading: IconButton(
          tooltip: 'Back to academic areas',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('${_academicAreaLabel(area)} departments'),
      ),
      body: SafeArea(top: false, child: _CatalogFrame(child: content)),
    );
  }
}

// Applies the same readable maximum width to every catalog state.
class _CatalogFrame extends StatelessWidget {
  const _CatalogFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTheme.contentWidth),
        child: child,
      ),
    );
  }
}

// One large catalog destination with an explicit accessibility label.
class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open $title',
      child: Semantics(
        button: true,
        label: 'Open $title. $subtitle',
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: CircleAvatar(
                        radius: 20,
                        child: Icon(icon, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(subtitle),
                        ],
                      ),
                    ),
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

// Loading text states exactly which catalog level is being requested.
class _CatalogLoading extends StatelessWidget {
  const _CatalogLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Loading $label',
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 10),
              Text('Loading $label...'),
            ],
          ),
        ),
      ),
    );
  }
}

// Empty and error states share one scrollable, retryable presentation.
class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
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
        Card(
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

// Exact labels prevent database capitalization from changing the FYP wording.
String _academicAreaLabel(AcademicArea area) {
  return area.displayName;
}

// Conservative matching avoids calling every authorization error "offline".
bool _looksLikeOfflineError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('unavailable') ||
      message.contains('network') ||
      message.contains('offline') ||
      message.contains('connection');
}
