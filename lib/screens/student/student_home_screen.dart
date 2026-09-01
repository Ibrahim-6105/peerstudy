// Beginner-friendly home page for the signed-in student area.
//
// This page deliberately explains the learning flow in plain language. It
// does not load sample records, so every subject shortcut always represents a
// real subject selected from the protected catalog.

// Material supplies the cards, buttons, icons, spacing, and text widgets.
import 'package:flutter/material.dart';

// The typed School and fixed corrected-master name are displayed on Home.
import 'package:peerstudy/models/subject.dart';

// The simple repository and selection store provide live data and recent choice.
import 'package:peerstudy/providers/subject_provider.dart';

// The workspace screen is opened directly without adding a named app route.
import 'package:peerstudy/screens/student/student_subject_workspace_screen.dart';

// Shared layout values keep this page aligned with the rest of the app.
import 'package:peerstudy/theme/app_theme.dart';

// StudentHomeScreen is the first tab shown after a student signs in.
class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({required this.onBrowseSubjects, super.key});

  // The shell supplies this callback so the main button can select tab two.
  final VoidCallback onBrowseSubjects;

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

// This ordinary State object owns only the School loading values on Home.
class _StudentHomeScreenState extends State<StudentHomeScreen> {
  // One repository performs the real School query.
  final SubjectRepository _repository = SubjectRepository();

  // These three fields are enough for loading, success, and error states.
  AcademicSchool? _school;
  bool _isLoading = true;
  bool _hasError = false;

  // Load real backend data when Flutter first opens this tab.
  @override
  void initState() {
    super.initState();
    _loadSchool();
  }

  // A normal async method plus setState replaces the previous provider.
  Future<void> _loadSchool() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final school = await _repository.fetchSchool();
      if (!mounted) return;
      setState(() {
        _school = school;
        _isLoading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _school = null;
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Home reads the most recent genuine catalog choice from a plain field.
    final selectedSubject = StudentSelectionStore.instance.selectedSubject;

    // Center and ConstrainedBox keep paragraphs readable on wide displays.
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppTheme.contentWidth),
          // ListView makes all home content reachable on a small phone.
          child: ListView(
            padding: AppTheme.pagePadding,
            children: [
              // No local sample School is substituted if the database is empty.
              if (_isLoading)
                const _SchoolContextCard.loading()
              else if (_hasError || _school == null)
                _SchoolContextCard.error(onRetry: _loadSchool)
              else
                _SchoolContextCard.ready(
                  school: _school!,
                  onBrowseSubjects: widget.onBrowseSubjects,
                ),

              // A genuine previous selection appears only after the user chose it.
              if (selectedSubject != null) ...[
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'Continue studying',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          selectedSubject.name,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        // A subject code is optional, so empty space is avoided.
                        if (selectedSubject.code.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text('Subject code: ${selectedSubject.code}'),
                        ],
                        const SizedBox(height: 10),
                        Tooltip(
                          message: 'Continue ${selectedSubject.name}',
                          child: SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              // MaterialPageRoute keeps this new flow independent
                              // from the existing named-route configuration.
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) =>
                                        StudentSubjectWorkspaceScreen(
                                          subject: selectedSubject,
                                        ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Open subject workspace'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  'Inside every subject',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),

              // A simple column stays tidy on narrow phones and is easy to read.
              Column(
                children: const [
                  _HomeFeatureCard(
                    icon: Icons.picture_as_pdf_outlined,
                    title: 'Official Materials',
                    description: 'Find approved lecture PDF records.',
                  ),
                  _HomeFeatureCard(
                    icon: Icons.psychology_alt_outlined,
                    title: 'AI Quiz',
                    description:
                        'Practice with ten questions from approved materials.',
                  ),
                  _HomeFeatureCard(
                    icon: Icons.people_alt_outlined,
                    title: 'Community',
                    description: 'Share subject posts and comments with peers.',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// This card makes the top-level School explicit before the two Academic Areas.
class _SchoolContextCard extends StatelessWidget {
  _SchoolContextCard.ready({
    required AcademicSchool school,
    required this.onBrowseSubjects,
  }) : title = school.name,
       message =
           'Choose Information Technology or Engineering, then continue '
           'through a Department to one active Subject.',
       isLoading = false,
       isError = false,
       onRetry = null;

  const _SchoolContextCard.loading()
    : title = peerStudySchoolName,
      message = 'Loading the School academic catalog...',
      isLoading = true,
      isError = false,
      onBrowseSubjects = null,
      onRetry = null;

  const _SchoolContextCard.error({required this.onRetry})
    : title = peerStudySchoolName,
      message =
          'The School catalog is unavailable. Check your connection and retry.',
      isLoading = false,
      isError = true,
      onBrowseSubjects = null;

  final String title;
  final String message;
  final bool isLoading;
  final bool isError;
  final VoidCallback? onBrowseSubjects;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 6),
            Text(message),
            const SizedBox(height: 12),
            if (isLoading)
              const LinearProgressIndicator()
            else
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.icon(
                  onPressed: isError ? onRetry : onBrowseSubjects,
                  icon: Icon(
                    isError ? Icons.refresh_rounded : Icons.menu_book_rounded,
                  ),
                  label: Text(
                    isError ? 'Try again' : 'Browse academic catalog',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// A small non-interactive card explains one workspace area.
class _HomeFeatureCard extends StatelessWidget {
  const _HomeFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  // The icon gives a quick visual clue for sighted users.
  final IconData icon;

  // The title matches the wording used in the subject workspace tabs.
  final String title;

  // The description tells a beginner what the area is for.
  final String description;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title. $description',
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(title, style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(description),
        ),
      ),
    );
  }
}
