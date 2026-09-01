// This page lets the user choose PeerStudy's light or dark appearance.
//
// Beginner note:
// The page edits one temporary AppSettings copy. Save writes that complete copy
// to local device storage. No Supabase account or academic row changes here.

// Material supplies SafeArea, buttons, icons, and the segmented control.
import 'package:flutter/material.dart';

// SettingsNotifier is a plain callback service, not a state-management package.
import 'package:peerstudy/providers/settings_provider.dart';

// AppTheme supplies the shared readable maximum width and page padding.
import 'package:peerstudy/theme/app_theme.dart';

// SettingsScreen may receive an in-memory service from focused widget tests.
class SettingsScreen extends StatefulWidget {
  // The real application omits settingsService and uses the shared singleton.
  const SettingsScreen({super.key, this.settingsService});

  // Tests can keep storage isolated without changing production behavior.
  final SettingsNotifier? settingsService;

  // Create the local draft state.
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

// This state uses ordinary setState and one service callback.
class _SettingsScreenState extends State<SettingsScreen> {
  // Null means the page is displaying the last successfully saved snapshot.
  AppSettings? _draft;

  // This is the one small settings service used while the page is mounted.
  late final SettingsNotifier _settings;

  // Connect the page to local storage once.
  @override
  void initState() {
    super.initState();

    // Pick the focused-test service or the real singleton.
    _settings = widget.settingsService ?? SettingsNotifier.instance;

    // The callback only asks this visible widget to rebuild.
    _settings.addListener(_settingsChanged);

    // Standalone tests may open this page without running application startup.
    if (_settings.state.isLoading) _settings.load();
  }

  // Rebuild after a local settings read, save, or rollback.
  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  // Remove the callback when navigation closes this page.
  @override
  void dispose() {
    _settings.removeListener(_settingsChanged);
    super.dispose();
  }

  // Build a compact phone-safe Light/Dark preference page.
  @override
  Widget build(BuildContext context) {
    // Read the true service state and any unsaved local choice.
    final state = _settings.state;
    final draft = _draft ?? state.settings;

    // Old system values migrate visually to the requested white Light mode.
    final selectedTheme = draft.themeMode == ThemeMode.dark
        ? ThemeMode.dark
        : ThemeMode.light;

    // Read active colors once for the explanatory panel.
    final colors = Theme.of(context).colorScheme;

    // Scaffold supplies the active white or dark page background.
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      // SafeArea keeps every control clear of notches and navigation gestures.
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTheme.contentWidth),
            // ListView keeps controls reachable on short phones.
            child: ListView(
              padding: AppTheme.pagePadding,
              children: [
                // Use the compact section title from the shared theme.
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),

                // Explain the two simple options without technical wording.
                const SizedBox(height: 4),
                Text(
                  'Light is the default. Choose Dark for a softer night view.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),

                // Keep the selector clearly separated from its explanation.
                const SizedBox(height: 14),

                // A quiet bordered panel groups the choice without a dialog.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border.all(color: colors.outline),
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // This small label identifies the device-only setting.
                      Text(
                        'Theme on this device',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),

                      // SegmentedButton makes the only two choices obvious.
                      const SizedBox(height: 10),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined, size: 17),
                            label: Text('Light'),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined, size: 17),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: <ThemeMode>{selectedTheme},
                        showSelectedIcon: false,
                        onSelectionChanged: state.isSaving
                            ? null
                            : (selection) {
                                // A segmented control always returns one value.
                                final themeMode = selection.first;

                                // setState stores only this page's unsaved draft.
                                setState(
                                  () => _draft = draft.copyWith(
                                    themeMode: themeMode,
                                  ),
                                );
                              },
                      ),
                    ],
                  ),
                ),

                // A storage error remains visible and accessible after rollback.
                if (state.error != null) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      state.error!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.error),
                    ),
                  ),
                ],

                // The compact primary button saves the complete snapshot.
                const SizedBox(height: 16),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: state.isSaving ? null : () => _save(draft),
                    icon: state.isSaving
                        ? SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.onPrimary,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(state.isSaving ? 'Saving...' : 'Save settings'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Save the draft, then return the page to the service's true snapshot.
  Future<void> _save(AppSettings draft) async {
    // The notifier writes one complete rollback-safe settings object.
    final saved = await _settings.save(draft);

    // Stop if navigation removed the page while storage was answering.
    if (!mounted) return;

    // Null makes build read the saved or rolled-back service snapshot again.
    setState(() => _draft = null);

    // Confirm success or failure with one short message.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? 'Settings saved.' : 'Settings were not saved.'),
      ),
    );
  }
}
