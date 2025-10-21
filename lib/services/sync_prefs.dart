// lib/services/sync_prefs.dart
import 'package:shared_preferences/shared_preferences.dart';

class SyncPrefs {
  static const _key = 'cloud_enabled_v1';

  static Future<bool> isCloudEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_key) ?? false;
    // default = false → offline-first
  }

  static Future<void> setCloudEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, v);
  }
}
