// Browser fallback for PeerStudy device settings.

import 'package:shared_preferences/shared_preferences.dart';

const String _settingsBlobKey = 'peerstudySettingsV1';

class SettingsStorage {
  SettingsStorage._();

  static final SettingsStorage instance = SettingsStorage._();

  // Browser preferences remain one atomic JSON string.
  Future<String?> readBlob() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_settingsBlobKey);
  }

  // The plugin maps this value to browser-local storage.
  Future<bool> writeBlob(String value) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.setString(_settingsBlobKey, value);
  }

  // Older web builds used the same plugin with separate fallback keys.
  Future<Map<String, Object?>> readLegacyValues() async {
    final preferences = await SharedPreferences.getInstance();
    return <String, Object?>{
      'blob': preferences.getString(_settingsBlobKey),
      'themeMode': preferences.getString('themeMode'),
      'lastAreaId': preferences.getString('lastAreaId'),
      'lastDepartmentId': preferences.getString('lastDepartmentId'),
      'lastSubjectId': preferences.getString('lastSubjectId'),
    };
  }
}
