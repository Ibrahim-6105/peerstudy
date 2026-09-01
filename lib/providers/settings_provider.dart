// Stores the few device preferences that PeerStudy really needs.
//
// Beginner note:
// Supabase owns accounts and academic data. This small service stores only the
// appearance choice and the last opened academic path in the phone's SQLite
// row. The local row is helpful navigation memory, never authoritative data.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:peerstudy/services/settings_storage.dart';

// These small function types let tests replace SQLite with in-memory storage.
typedef SettingsBlobReader = Future<String?> Function();
typedef SettingsBlobWriter = Future<bool> Function(String value);
typedef SettingsLegacyReader = Future<Map<String, Object?>> Function();

// AppSettings is the complete non-authoritative device preference snapshot.
class AppSettings {
  const AppSettings({
    // A fresh installation always starts with the requested white light theme.
    this.themeMode = ThemeMode.light,
    this.lastAreaId,
    this.lastDepartmentId,
    this.lastSubjectId,
  });

  // PeerStudy supports one clear light choice and one optional dark choice.
  final ThemeMode themeMode;

  // These IDs only reopen the last path; Supabase validates every real row.
  final String? lastAreaId;
  final String? lastDepartmentId;
  final String? lastSubjectId;

  // copyWith makes one new immutable snapshot after a preference changes.
  AppSettings copyWith({
    ThemeMode? themeMode,
    String? lastAreaId,
    String? lastDepartmentId,
    String? lastSubjectId,
    bool clearLastArea = false,
    bool clearLastDepartment = false,
    bool clearLastSubject = false,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      lastAreaId: clearLastArea ? null : lastAreaId ?? this.lastAreaId,
      lastDepartmentId: clearLastDepartment
          ? null
          : lastDepartmentId ?? this.lastDepartmentId,
      lastSubjectId: clearLastSubject
          ? null
          : lastSubjectId ?? this.lastSubjectId,
    );
  }

  // Only current settings are written to the device snapshot.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'themeMode': themeMode.name,
      'lastAreaId': lastAreaId,
      'lastDepartmentId': lastDepartmentId,
      'lastSubjectId': lastSubjectId,
    };
  }

  // Extra keys from an older app version are deliberately ignored.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    final lastAreaId = json['lastAreaId'];
    final lastDepartmentId = json['lastDepartmentId'];
    final lastSubjectId = json['lastSubjectId'];

    // A malformed ID snapshot is rejected instead of being partly trusted.
    if ((lastAreaId != null && lastAreaId is! String) ||
        (lastDepartmentId != null && lastDepartmentId is! String) ||
        (lastSubjectId != null && lastSubjectId is! String)) {
      throw const FormatException('Saved settings have invalid field types.');
    }

    return AppSettings(
      themeMode: _themeModeFromName(json['themeMode'] as String?),
      lastAreaId: lastAreaId as String?,
      lastDepartmentId: lastDepartmentId as String?,
      lastSubjectId: lastSubjectId as String?,
    );
  }
}

// SettingsState adds loading, saving, and safe error information for the UI.
class SettingsState {
  const SettingsState({
    this.settings = const AppSettings(),
    this.isLoading = true,
    this.isSaving = false,
    this.error,
  });

  final AppSettings settings;
  final bool isLoading;
  final bool isSaving;
  final String? error;

  // The explicit clear flag allows a successful operation to remove an error.
  SettingsState copyWith({
    AppSettings? settings,
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
  }) {
    return SettingsState(
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: clearError ? null : error ?? this.error,
    );
  }
}

// SettingsNotifier performs the one-row read and atomic snapshot writes.
class SettingsNotifier {
  // The app shares this one small service instead of a state-management package.
  static final SettingsNotifier instance = SettingsNotifier();

  SettingsNotifier({
    SettingsBlobReader? blobReader,
    SettingsBlobWriter? blobWriter,
    SettingsLegacyReader? legacyReader,
  }) : _blobReader = blobReader ?? SettingsStorage.instance.readBlob,
       _blobWriter = blobWriter ?? SettingsStorage.instance.writeBlob,
       _legacyReader =
           legacyReader ?? SettingsStorage.instance.readLegacyValues;

  final SettingsBlobReader _blobReader;
  final SettingsBlobWriter _blobWriter;
  final SettingsLegacyReader _legacyReader;

  // The latest simple immutable snapshot is kept in one private field.
  SettingsState _state = const SettingsState();

  // Screens read the current state through this getter.
  SettingsState get state => _state;

  // Plain callbacks let a StatefulWidget call setState after a change.
  final Set<VoidCallback> _listeners = <VoidCallback>{};

  // Add one screen callback while that screen is visible.
  void addListener(VoidCallback listener) => _listeners.add(listener);

  // Remove the callback from dispose so an old screen is never rebuilt.
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  // Tests or short-lived custom services may release every callback at once.
  void dispose() => _listeners.clear();

  // Assigning state informs the few interested StatefulWidgets.
  set state(SettingsState value) {
    _state = value;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  // Load a current snapshot, or migrate the useful values from the old store.
  Future<void> load() async {
    try {
      final savedBlob = await _blobReader();
      if (savedBlob != null) {
        state = SettingsState(
          isLoading: false,
          settings: _settingsFromBlob(savedBlob),
        );
        return;
      }

      // AppSettings.fromJson ignores unknown fields and keeps supported values.
      final legacy = await _legacyReader();
      final legacyBlob = legacy['blob'];
      final migratedSettings = legacyBlob is String
          ? _settingsFromBlob(legacyBlob)
          : AppSettings(
              themeMode: _themeModeFromName(legacy['themeMode'] as String?),
              lastAreaId: legacy['lastAreaId'] as String?,
              lastDepartmentId: legacy['lastDepartmentId'] as String?,
              lastSubjectId: legacy['lastSubjectId'] as String?,
            );

      state = SettingsState(isLoading: false, settings: migratedSettings);

      // Migration is best effort because a readable old value is still useful.
      try {
        await _blobWriter(jsonEncode(migratedSettings.toJson()));
      } catch (_) {
        // A later explicit save can retry the local write.
      }
    } catch (_) {
      state = const SettingsState(
        isLoading: false,
        error: 'Saved settings could not be loaded.',
      );
    }
  }

  // Save one complete snapshot and roll back memory if SQLite rejects it.
  Future<bool> save(AppSettings nextSettings) async {
    final previousSettings = state.settings;
    state = state.copyWith(
      settings: nextSettings,
      isSaving: true,
      clearError: true,
    );

    try {
      final saved = await _blobWriter(jsonEncode(nextSettings.toJson()));
      if (!saved) throw StateError('A preference write returned false.');
      state = state.copyWith(isSaving: false, clearError: true);
      return true;
    } catch (_) {
      state = state.copyWith(
        settings: previousSettings,
        isSaving: false,
        error: 'Settings were not saved. Your previous choices were restored.',
      );
      return false;
    }
  }

  // Remember the last complete academic path after a Subject opens.
  Future<bool> rememberSelection({
    required String areaId,
    required String departmentId,
    required String subjectId,
  }) {
    return save(
      state.settings.copyWith(
        lastAreaId: areaId,
        lastDepartmentId: departmentId,
        lastSubjectId: subjectId,
      ),
    );
  }

  // Remove account-specific navigation history during every sign-out.
  Future<void> clearAccountSelection() async {
    final clearedSettings = state.settings.copyWith(
      clearLastArea: true,
      clearLastDepartment: true,
      clearLastSubject: true,
    );

    // Clear memory first so the next account never sees another user's path.
    state = state.copyWith(
      settings: clearedSettings,
      isSaving: true,
      clearError: true,
    );

    try {
      final saved = await _blobWriter(jsonEncode(clearedSettings.toJson()));
      if (!saved) throw StateError('The cleared snapshot was not saved.');
      state = state.copyWith(isSaving: false, clearError: true);
    } catch (_) {
      // Privacy takes priority: keep memory cleared even if SQLite is damaged.
      state = state.copyWith(
        settings: clearedSettings,
        isSaving: false,
        error: 'Local study history could not be fully cleared.',
      );
    }
  }
}

// Decode one complete JSON object from the SQLite row.
AppSettings _settingsFromBlob(String blob) {
  final decoded = jsonDecode(blob);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Saved settings are not an object.');
  }
  return AppSettings.fromJson(decoded);
}

// Dark is kept only when the user explicitly selected it.
// Old `system` values and malformed values migrate to the white light design.
ThemeMode _themeModeFromName(String? name) {
  // This simple condition is easier for a beginner than a migration table.
  return name == ThemeMode.dark.name ? ThemeMode.dark : ThemeMode.light;
}
