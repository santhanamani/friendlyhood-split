import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference {
  system,
  light,
  dark;

  String get label => switch (this) {
        AppThemePreference.system => 'System default',
        AppThemePreference.light => 'Light mode',
        AppThemePreference.dark => 'Dark mode',
      };

  String get description => switch (this) {
        AppThemePreference.system => 'Follow your phone appearance',
        AppThemePreference.light => 'Always use a bright appearance',
        AppThemePreference.dark => 'Always use a dark appearance',
      };

  IconData get icon => switch (this) {
        AppThemePreference.system => Icons.brightness_auto_rounded,
        AppThemePreference.light => Icons.light_mode_rounded,
        AppThemePreference.dark => Icons.dark_mode_rounded,
      };
}

class AppThemeController extends ChangeNotifier {
  AppThemeController._(this._preferences, this._preference);

  static const _preferenceKey = 'app_theme_preference';

  final SharedPreferences _preferences;
  AppThemePreference _preference;

  AppThemePreference get preference => _preference;

  ThemeMode get themeMode => switch (_preference) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      };

  static Future<AppThemeController> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_preferenceKey);
    final preference = AppThemePreference.values.firstWhere(
      (item) => item.name == stored,
      orElse: () => AppThemePreference.dark,
    );
    return AppThemeController._(preferences, preference);
  }

  Future<void> setPreference(AppThemePreference value) async {
    if (_preference == value) return;
    _preference = value;
    notifyListeners();
    await _preferences.setString(_preferenceKey, value.name);
  }
}
