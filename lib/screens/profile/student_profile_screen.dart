// Student Profile tab backed by the corrected Supabase database.
//
// Beginner note:
// Supabase Auth proves who signed in. The `profiles` table supplies the full
// name, role, and status. Recent activity is read only from rows owned by that
// same user ID; no sample activity or estimated count is displayed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:peerstudy/models/app_user.dart';
import 'package:peerstudy/providers/settings_provider.dart';
import 'package:peerstudy/providers/subject_provider.dart';
import 'package:peerstudy/routes/app_routes.dart';
import 'package:peerstudy/screens/profile/community_guidelines_screen.dart';
import 'package:peerstudy/screens/profile/feedback_screen.dart';
import 'package:peerstudy/screens/profile/student_account_screen.dart';
import 'package:peerstudy/services/supabase_service.dart';
import 'package:peerstudy/services/auth_service.dart';
import 'package:peerstudy/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Only a small newest-first window is needed on the Profile tab.
const int _activityDisplayLimit = 5;

// This small model prevents raw PostgreSQL maps from reaching widgets.
class StudentActivityEntry {
  const StudentActivityEntry({
    required this.title,
    required this.preview,
    required this.subjectId,
    required this.createdAt,
  });

  final String title;
  final String preview;

  // For a Post this contains the Community ID; for an Attempt it contains the
  // Quiz ID. The old field name is retained so existing simple tests compile.
  final String subjectId;
  final DateTime createdAt;
}

// A section is either a real list (which may be empty) or safely unavailable.
class StudentActivitySection {
  const StudentActivitySection.available(this.items)
    : unavailableMessage = null;

  const StudentActivitySection.unavailable(this.unavailableMessage)
    : items = const <StudentActivityEntry>[];

  final List<StudentActivityEntry> items;
  final String? unavailableMessage;

  bool get isUnavailable => unavailableMessage != null;
}

// Posts and quizzes fail independently so one problem does not hide both.
class StudentRecentActivity {
  const StudentRecentActivity({required this.posts, required this.quizzes});

  final StudentActivitySection posts;
  final StudentActivitySection quizzes;
}

// Tests may replace the cloud reader without initializing Supabase.
typedef StudentActivityLoader =
    Future<StudentRecentActivity> Function({
      required String userId,
      required String? areaId,
      required String? departmentId,
      required String? subjectId,
    });

// Tests may also replace the one allowed profile write.
typedef ProfileNameUpdater = Future<String> Function(String fullName);

// StudentActivityReader owns the two bounded Supabase queries.
class StudentActivityReader {
  StudentActivityReader([SupabaseClient? client]) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  // A test client may be supplied; the real app uses the initialized singleton.
  SupabaseClient get _client {
    final injectedClient = _injectedClient;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseService.isReady) {
      throw StateError('Supabase is not ready.');
    }
    return SupabaseService.client;
  }

  // The academic IDs remain accepted for an easy compatible widget boundary.
  // Activity itself is account-wide and always filters by the signed-in UID.
  Future<StudentRecentActivity> load({
    required String userId,
    required String? areaId,
    required String? departmentId,
    required String? subjectId,
  }) async {
    try {
      final authUser = _client.auth.currentUser;
      if (authUser == null || authUser.id != userId) {
        return _unavailableActivity(
          'Recent activity is unavailable until you sign in again.',
        );
      }

      final sections = await Future.wait<StudentActivitySection>([
        _readPosts(userId),
        _readQuizAttempts(userId),
      ]);
      return StudentRecentActivity(posts: sections[0], quizzes: sections[1]);
    } catch (_) {
      return _unavailableActivity(
        'Recent activity could not be loaded. Pull down or retry later.',
      );
    }
  }

  // Read only active Community Posts authored by this exact account.
  Future<StudentActivitySection> _readPosts(String userId) async {
    try {
      final response = await _client
          .from('community_posts')
          .select('body, community_id, created_at')
          .eq('author_id', userId)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(_activityDisplayLimit);

      final items = _rows(response)
          .map((row) {
            return StudentActivityEntry(
              title: 'Community post',
              preview: _safePreview(row['body']),
              subjectId: _safeText(row['community_id']),
              createdAt: _safeDate(row['created_at']),
            );
          })
          .toList(growable: false);

      return StudentActivitySection.available(items);
    } catch (_) {
      return const StudentActivitySection.unavailable(
        'Recent Community posts could not be loaded.',
      );
    }
  }

  // Read only submitted Quiz Attempts owned by this exact account.
  Future<StudentActivitySection> _readQuizAttempts(String userId) async {
    try {
      final response = await _client
          .from('quiz_attempts')
          .select('quiz_id, score, total, completed_at')
          .eq('student_id', userId)
          .eq('status', 'submitted')
          .order('completed_at', ascending: false)
          .limit(_activityDisplayLimit);

      final items = _rows(response)
          .map((row) {
            final score = _safeInteger(row['score']);
            final total = _safeInteger(row['total']);
            if (total != 10 || score < 0 || score > total) {
              throw const FormatException('Invalid quiz score.');
            }
            return StudentActivityEntry(
              title: 'AI quiz score: $score/$total',
              preview: 'Completed from one approved Subject material.',
              subjectId: _safeText(row['quiz_id']),
              createdAt: _safeDate(row['completed_at']),
            );
          })
          .toList(growable: false);

      return StudentActivitySection.available(items);
    } catch (_) {
      return const StudentActivitySection.unavailable(
        'Recent Quiz Attempts could not be loaded.',
      );
    }
  }
}

// StudentProfileTab is embedded inside the third Student shell destination.
class StudentProfileTab extends StatefulWidget {
  const StudentProfileTab({
    super.key,
    required this.onBrowseSubjects,
    this.isActive = true,
    this.activityLoader,
    this.profileNameUpdater,
    this.accountScreenBuilder,
    this.initialUser,
    this.settingsService,
  });

  final VoidCallback onBrowseSubjects;
  final bool isActive;
  final StudentActivityLoader? activityLoader;
  final ProfileNameUpdater? profileNameUpdater;
  final WidgetBuilder? accountScreenBuilder;

  // Tests may supply a user and in-memory settings without a cloud session.
  final AppUser? initialUser;
  final SettingsNotifier? settingsService;

  @override
  State<StudentProfileTab> createState() => _StudentProfileTabState();
}

class _StudentProfileTabState extends State<StudentProfileTab> {
  Future<StudentRecentActivity>? _activityFuture;
  String? _activityUserId;
  bool _isActivityLoading = false;
  bool _isUpdatingName = false;
  bool _isSigningOut = false;

  // A local copy makes a successful name edit visible immediately.
  AppUser? _localUser;

  // Device preferences live in one tiny service shared by the app.
  late final SettingsNotifier _settings;

  @override
  void initState() {
    super.initState();

    // Pick simple injected values for tests or production singletons for the app.
    _localUser = widget.initialUser;
    _settings = widget.settingsService ?? SettingsNotifier.instance;

    // These callbacks simply call setState; Riverpod is not needed.
    _settings.addListener(_settingsChanged);
    if (_settings.state.isLoading) _settings.load();

    // Refresh the trusted profile once when this tab is first created.
    if (widget.initialUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // A temporary network error must not erase an already verified profile.
        try {
          await AuthService.instance.refreshCurrentUser();
        } catch (_) {
          // Keep the last verified in-memory profile and allow a later retry.
        }
        if (mounted) setState(() {});
      });
    }
  }

  // Rebuild when a local preference finishes loading or saving.
  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_settingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _localUser ?? AuthService.instance.currentUser;
    final settingsState = _settings.state;

    // IndexedStack builds hidden pages; wait until Profile is actually opened.
    if (widget.isActive && user != null && _activityUserId != user.uid) {
      _beginActivityLoad(user.uid, settingsState.settings, rebuild: false);
    }

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppTheme.contentWidth),
          child: ListView(
            padding: AppTheme.pagePadding,
            children: [
              _ProfileHeader(
                user: user,
                isUpdating: _isUpdatingName,
                onEditName: user == null ? null : () => _editFullName(user),
              ),
              const SizedBox(height: 10),
              _AccountSummary(user: user),
              const SizedBox(height: 10),
              _StudySelectionCard(
                settingsState: settingsState,
                onBrowseSubjects: widget.onBrowseSubjects,
              ),
              const SizedBox(height: 16),
              _SectionHeading(
                title: 'Recent activity',
                subtitle: 'Your five newest Posts and Quiz Attempts.',
                action: IconButton(
                  tooltip: 'Refresh recent activity',
                  onPressed:
                      user == null || !widget.isActive || _isActivityLoading
                      ? null
                      : () => _reloadActivity(user.uid, settingsState.settings),
                  icon: _isActivityLoading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(height: 8),
              _RecentActivityPanel(
                future: _activityFuture,
                isActive: widget.isActive,
              ),
              const SizedBox(height: 16),
              const _SectionHeading(title: 'Profile and preferences'),
              const SizedBox(height: 6),
              _ProfileLinkTile(
                icon: Icons.settings_outlined,
                title: 'Settings',
                onTap: () => Navigator.pushNamed(context, AppRoutes.settings),
              ),
              _ProfileLinkTile(
                icon: Icons.manage_accounts_outlined,
                title: 'Account',
                onTap: _openAccountScreen,
              ),
              const SizedBox(height: 12),
              const _SectionHeading(title: 'Help and information'),
              const SizedBox(height: 6),
              _ProfileLinkTile(
                icon: Icons.groups_outlined,
                title: 'Community Guidelines',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const CommunityGuidelinesScreen(),
                  ),
                ),
              ),
              _ProfileLinkTile(
                icon: Icons.feedback_outlined,
                title: 'Feedback and Support',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const FeedbackScreen(),
                  ),
                ),
              ),
              _ProfileLinkTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                onTap: () => Navigator.pushNamed(context, AppRoutes.privacy),
              ),
              _ProfileLinkTile(
                icon: Icons.description_outlined,
                title: 'Terms of Service',
                onTap: () => Navigator.pushNamed(context, AppRoutes.terms),
              ),
              _ProfileLinkTile(
                icon: Icons.info_outline,
                title: 'About PeerStudy',
                onTap: () => Navigator.pushNamed(context, AppRoutes.about),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _isSigningOut ? null : _confirmSignOut,
                  icon: _isSigningOut
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout_rounded),
                  label: Text(_isSigningOut ? 'Signing out...' : 'Sign Out'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Use a test loader when supplied; production reads the real Supabase rows.
  Future<StudentRecentActivity> _loadActivity(
    String userId,
    AppSettings settings,
  ) async {
    final loader = widget.activityLoader ?? StudentActivityReader().load;
    try {
      return await Future<StudentRecentActivity>.sync(
        () => loader(
          userId: userId,
          areaId: settings.lastAreaId,
          departmentId: settings.lastDepartmentId,
          subjectId: settings.lastSubjectId,
        ),
      );
    } catch (_) {
      // Keep network, authorization, and malformed-response failures inside the
      // Profile UI instead of exposing an error Future to Flutter's framework.
      return _unavailableActivity(
        'Recent activity could not be loaded. Please try again.',
      );
    }
  }

  // Start one tracked request. Identity checks prevent an older request from
  // clearing the loading state of a newer account/session request.
  void _beginActivityLoad(
    String userId,
    AppSettings settings, {
    required bool rebuild,
  }) {
    final request = _loadActivity(userId, settings);

    void updateState() {
      _activityUserId = userId;
      _isActivityLoading = true;
      _activityFuture = request;
    }

    if (rebuild) {
      setState(updateState);
    } else {
      updateState();
    }
    unawaited(_finishActivityLoad(request));
  }

  // Restore the refresh control only for the request currently on screen.
  Future<void> _finishActivityLoad(
    Future<StudentRecentActivity> request,
  ) async {
    await request;
    if (!mounted || !identical(_activityFuture, request)) return;
    setState(() => _isActivityLoading = false);
  }

  // A manual refresh replaces the Future so FutureBuilder performs new reads.
  // The synchronous guard also covers two taps arriving before the next frame.
  void _reloadActivity(String userId, AppSettings settings) {
    if (_isActivityLoading) return;
    _beginActivityLoad(userId, settings, rebuild: true);
  }

  // Only full_name can be edited by a Student through the protected RPC.
  Future<void> _editFullName(AppUser user) async {
    final submitted = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _EditFullNameSheet(initialName: user.fullName),
    );

    if (submitted == null || submitted == user.fullName || !mounted) return;
    setState(() => _isUpdatingName = true);

    try {
      final savedName = await _updateFullName(submitted);
      if (!mounted) return;

      // Update the local service immediately with the trusted RPC result.
      final updatedUser = AppUser(
        uid: user.uid,
        fullName: savedName,
        email: user.email,
        role: user.role,
        isBlocked: user.isBlocked,
        status: user.status,
        version: user.version + 1,
        createdAt: user.createdAt,
        updatedAt: DateTime.now().toUtc(),
      );

      // Production also updates the shared auth snapshot used by other pages.
      if (widget.initialUser == null) {
        AuthService.instance.replaceCurrentUser(updatedUser);
      }
      setState(() => _localUser = updatedUser);
      _showMessage('Full name updated.');
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Your name could not be updated. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingName = false);
    }
  }

  // Call the injected test updater or the active-Student-only database RPC.
  Future<String> _updateFullName(String submitted) async {
    final customUpdater = widget.profileNameUpdater;
    if (customUpdater != null) return customUpdater(submitted);
    if (!SupabaseService.isReady) throw StateError('Supabase is not ready.');

    final response = await SupabaseService.client.rpc(
      'update_my_full_name',
      params: <String, Object?>{'p_full_name': submitted},
    );
    final row = _oneRow(response);
    final savedName = _normalizeName(_safeText(row['full_name']));
    if (_validateFullName(savedName) != null) {
      throw const FormatException('The profile RPC returned an invalid name.');
    }
    return savedName;
  }

  // Account has a direct material route because no named route is required.
  void _openAccountScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            widget.accountScreenBuilder ??
            (context) => const StudentAccountScreen(),
      ),
    );
  }

  // Sign-out always confirms, clears account-scoped state, and returns to Login.
  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.logout_rounded),
          title: const Text('Sign out of PeerStudy?'),
          content: const Text(
            'You will need your LIMU email and password to sign in again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSigningOut = true);
    // Clear remote auth plus account-specific values held on this phone.
    await AuthService.instance.signOut();
    await _settings.clearAccountSelection();
    StudentSelectionStore.instance.clear();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (route) => false,
    );
  }

  // Display only reviewed messages, never raw PostgREST/Auth exceptions.
  void _showMessage(String message, {bool isError = false}) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colors.error : null,
      ),
    );
  }
}

// The sheet owns its controller for the complete opening/closing animation.
// A sheet keeps the form visible when the phone keyboard opens.
class _EditFullNameSheet extends StatefulWidget {
  const _EditFullNameSheet({required this.initialName});

  final String initialName;

  @override
  State<_EditFullNameSheet> createState() => _EditFullNameSheetState();
}

class _EditFullNameSheetState extends State<_EditFullNameSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Edit full name',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controller,
              autofocus: true,
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: _validateFullName,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (!_formKey.currentState!.validate()) return;
                      Navigator.of(
                        context,
                      ).pop(_normalizeName(_controller.text));
                    },
                    child: const Text('Save name'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Header values come only from the plain AuthService.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.isUpdating,
    required this.onEditName,
  });

  final AppUser? user;
  final bool isUpdating;
  final VoidCallback? onEditName;

  @override
  Widget build(BuildContext context) {
    final displayName = user?.fullName.trim().isNotEmpty == true
        ? user!.fullName.trim()
        : 'Student';
    final email = user?.email ?? 'Account details are loading';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(radius: 24, child: Text(_initials(displayName))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(email),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit full name',
              onPressed: isUpdating ? null : onEditName,
              icon: isUpdating
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

// Role and lifecycle status come directly from the trusted profile.
class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.badge_outlined, size: 18),
          label: Text('Role: ${_titleCase(user?.role ?? 'student')}'),
        ),
        Chip(
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.shield_outlined, size: 18),
          label: Text('Status: ${user?.accountStatusLabel ?? 'Loading'}'),
        ),
      ],
    );
  }
}

// The current selected models provide friendly labels for the local path IDs.
class _StudySelectionCard extends StatelessWidget {
  const _StudySelectionCard({
    required this.settingsState,
    required this.onBrowseSubjects,
  });

  final SettingsState settingsState;
  final VoidCallback onBrowseSubjects;

  @override
  Widget build(BuildContext context) {
    final selection = StudentSelectionStore.instance;
    final area = selection.selectedArea;
    final department = selection.selectedDepartment;
    final subject = selection.selectedSubject;
    final hasSavedPath = settingsState.settings.lastSubjectId != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.school_outlined),
                const SizedBox(width: 10),
                Text(
                  'Current study path',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              area != null && department != null && subject != null
                  ? '${area.displayName} - ${department.name}\n'
                        '${subject.code} - ${subject.name}'
                  : hasSavedPath
                  ? 'A recent Subject is saved on this device. Open the '
                        'catalog to validate it with Supabase.'
                  : 'Choose a Subject to begin studying.',
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onBrowseSubjects,
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Browse subjects'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// A section heading can optionally expose one compact trailing action.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.subtitle, this.action});

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!),
              ],
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

// FutureBuilder represents loading, hidden, and the two real result sections.
class _RecentActivityPanel extends StatelessWidget {
  const _RecentActivityPanel({required this.future, required this.isActive});

  final Future<StudentRecentActivity>? future;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    if (!isActive) {
      return const _ActivityMessage('Open Profile to load recent activity.');
    }
    if (future == null) {
      return const _ActivityMessage('Sign in to load recent activity.');
    }

    return FutureBuilder<StudentRecentActivity>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox.square(
                  dimension: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          );
        }
        final activity = snapshot.data;
        if (activity == null) {
          return const _ActivityMessage('Recent activity could not be loaded.');
        }
        return Column(
          children: [
            _ActivitySectionCard(
              title: 'Recent Community posts',
              icon: Icons.forum_outlined,
              section: activity.posts,
            ),
            const SizedBox(height: 10),
            _ActivitySectionCard(
              title: 'Recent Quiz Attempts',
              icon: Icons.quiz_outlined,
              section: activity.quizzes,
            ),
          ],
        );
      },
    );
  }
}

// One card displays either honest rows, an honest empty state, or a safe error.
class _ActivitySectionCard extends StatelessWidget {
  const _ActivitySectionCard({
    required this.title,
    required this.icon,
    required this.section,
  });

  final String title;
  final IconData icon;
  final StudentActivitySection section;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (section.isUnavailable)
              Text(section.unavailableMessage!)
            else if (section.items.isEmpty)
              const Text('No activity yet.')
            else
              for (var index = 0; index < section.items.length; index++) ...[
                if (index > 0) const Divider(height: 20),
                _ActivityRow(entry: section.items[index]),
              ],
          ],
        ),
      ),
    );
  }
}

// Activity rows deliberately omit private quiz answers and raw database IDs.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final StudentActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 3),
        Text(entry.preview),
        const SizedBox(height: 3),
        Text(
          _formatDate(entry.createdAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

// A small card displays a single activity/session message.
class _ActivityMessage extends StatelessWidget {
  const _ActivityMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(14), child: Text(message)),
    );
  }
}

// Repeated profile navigation rows use one accessible touch target.
class _ProfileLinkTile extends StatelessWidget {
  const _ProfileLinkTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

// Both Post and Quiz queries use the same fail-closed result conversion.
List<Map<String, dynamic>> _rows(Object? response) {
  if (response is! List) throw const FormatException('Expected a row list.');
  return response
      .map((row) {
        if (row is! Map) throw const FormatException('Expected a row object.');
        return Map<String, dynamic>.from(row);
      })
      .toList(growable: false);
}

// PostgreSQL composite RPC responses may be one object or a one-item list.
Map<String, dynamic> _oneRow(Object? response) {
  if (response is Map) return Map<String, dynamic>.from(response);
  final rows = _rows(response);
  if (rows.length != 1) {
    throw const FormatException('Expected one profile row.');
  }
  return rows.single;
}

// Build one unavailable result without repeating its safe message.
StudentRecentActivity _unavailableActivity(String message) {
  return StudentRecentActivity(
    posts: StudentActivitySection.unavailable(message),
    quizzes: StudentActivitySection.unavailable(message),
  );
}

// Normalize whitespace in exactly the same way as registration/profile RPCs.
String _normalizeName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

// Full names must satisfy the corrected 2-100 character database rule.
String? _validateFullName(String? value) {
  final normalized = _normalizeName(value ?? '');
  if (normalized.length < 2) return 'Enter your full name.';
  if (normalized.length > 100) return 'Use 100 characters or fewer.';
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized)) {
    return 'The name contains unsupported characters.';
  }
  return null;
}

// Empty or very long Post text never damages the profile layout.
String _safePreview(Object? value) {
  final text = _safeText(value).replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return 'Post text unavailable';
  return text.length <= 140 ? text : '${text.substring(0, 137)}...';
}

// Convert a required database text value without trusting its runtime type.
String _safeText(Object? value) => value is String ? value.trim() : '';

// Quiz scores are integers even if a test supplies a generic numeric value.
int _safeInteger(Object? value) => value is num ? value.toInt() : -1;

// Supabase returns ISO-8601 timestamps; invalid data falls back to epoch UTC.
DateTime _safeDate(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

// Show a simple locale-independent date without adding another package.
String _formatDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

// The avatar uses at most the first two words of the full name.
String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  return words.where((word) => word.isNotEmpty).take(2).map((word) {
    return word.substring(0, 1).toUpperCase();
  }).join();
}

// Lowercase server role strings are shown in a normal readable form.
String _titleCase(String value) {
  if (value.isEmpty) return 'Unknown';
  return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
}
