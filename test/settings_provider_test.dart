// Tests for the small rollback-safe device preference snapshot.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerstudy/providers/settings_provider.dart';
import 'package:peerstudy/screens/profile/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saves and reloads one complete supported settings snapshot', () async {
    final storage = _MemorySettingsStorage();
    final notifier = _notifier(storage);
    await notifier.load();

    const next = AppSettings(
      themeMode: ThemeMode.dark,
      lastAreaId: 'area-it',
      lastDepartmentId: 'department-software',
      lastSubjectId: 'subject-data-structures',
    );
    expect(await notifier.save(next), isTrue);

    final stored = jsonDecode(storage.blob!) as Map<String, dynamic>;
    expect(stored['themeMode'], 'dark');
    expect(stored['lastAreaId'], 'area-it');
    expect(stored['lastDepartmentId'], 'department-software');
    expect(stored['lastSubjectId'], 'subject-data-structures');
    expect(stored.containsKey('cacheOnWifiOnly'), isFalse);
    expect(stored.containsKey('showModeratorBadges'), isFalse);

    final reloaded = _notifier(storage);
    await reloaded.load();
    expect(reloaded.state.settings.themeMode, ThemeMode.dark);
    expect(reloaded.state.settings.lastAreaId, 'area-it');
    expect(reloaded.state.settings.lastSubjectId, 'subject-data-structures');

    notifier.dispose();
    reloaded.dispose();
  });

  test('failed SQLite-style write restores memory and disk snapshot', () async {
    const previous = AppSettings(
      themeMode: ThemeMode.light,
      lastAreaId: 'area-engineering',
      lastDepartmentId: 'department-mechatronics',
      lastSubjectId: 'subject-control-systems',
    );
    final previousBlob = jsonEncode(previous.toJson());
    final storage = _MemorySettingsStorage(blob: previousBlob);
    final notifier = _notifier(storage);
    await notifier.load();

    storage.rejectWrites = true;
    final saved = await notifier.save(
      previous.copyWith(themeMode: ThemeMode.dark),
    );

    expect(saved, isFalse);
    expect(notifier.state.settings.themeMode, ThemeMode.light);
    expect(notifier.state.error, contains('previous choices'));
    expect(storage.blob, previousBlob);
    notifier.dispose();
  });

  testWidgets('failed save restores the previous theme on screen', (
    tester,
  ) async {
    const previous = AppSettings(themeMode: ThemeMode.light);
    final previousBlob = jsonEncode(previous.toJson());
    final storage = _MemorySettingsStorage(blob: previousBlob);
    final notifier = _notifier(storage);
    await notifier.load();
    storage.rejectWrites = true;

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settingsService: notifier)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Light'), findsOneWidget);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();

    expect(notifier.state.settings.themeMode, ThemeMode.light);
    expect(storage.blob, previousBlob);
    expect(
      find.text(
        'Settings were not saved. Your previous choices were restored.',
      ),
      findsOneWidget,
    );
    expect(find.text('Settings were not saved.'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
  });

  test('sign-out clears all three recent selections in one snapshot', () async {
    final storage = _MemorySettingsStorage(
      blob: jsonEncode(
        const AppSettings(
          themeMode: ThemeMode.dark,
          lastAreaId: 'area-engineering',
          lastDepartmentId: 'department-interior-design',
          lastSubjectId: 'subject-design-studio',
        ).toJson(),
      ),
    );
    final notifier = _notifier(storage);
    await notifier.load();
    await notifier.clearAccountSelection();

    final stored = jsonDecode(storage.blob!) as Map<String, dynamic>;
    expect(stored['lastAreaId'], isNull);
    expect(stored['lastDepartmentId'], isNull);
    expect(stored['lastSubjectId'], isNull);
    expect(stored['themeMode'], 'dark');
    notifier.dispose();
  });

  test('migration drops old offline and Moderator preference keys', () async {
    final legacyBlob = jsonEncode(<String, Object?>{
      'themeMode': 'dark',
      'cacheOnWifiOnly': true,
      'showModeratorBadges': true,
      'lastAreaId': 'area-it',
      'lastDepartmentId': 'department-network',
      'lastSubjectId': 'subject-routing',
    });
    final storage = _MemorySettingsStorage(
      legacyValues: <String, Object?>{'blob': legacyBlob},
    );
    final notifier = _notifier(storage);

    await notifier.load();

    expect(notifier.state.settings.themeMode, ThemeMode.dark);
    expect(notifier.state.settings.lastSubjectId, 'subject-routing');
    final migrated = jsonDecode(storage.blob!) as Map<String, dynamic>;
    expect(migrated.containsKey('cacheOnWifiOnly'), isFalse);
    expect(migrated.containsKey('showModeratorBadges'), isFalse);
    notifier.dispose();
  });
}

// Construct the service through the same tiny storage boundary as production.
SettingsNotifier _notifier(_MemorySettingsStorage storage) {
  return SettingsNotifier(
    blobReader: storage.read,
    blobWriter: storage.write,
    legacyReader: storage.readLegacy,
  );
}

// One in-memory string reproduces successful and rejected SQLite writes.
class _MemorySettingsStorage {
  _MemorySettingsStorage({this.blob, this.legacyValues = const {}});

  String? blob;
  final Map<String, Object?> legacyValues;
  bool rejectWrites = false;

  Future<String?> read() async => blob;

  Future<bool> write(String value) async {
    if (rejectWrites) return false;
    blob = value;
    return true;
  }

  Future<Map<String, Object?>> readLegacy() async => legacyValues;
}
