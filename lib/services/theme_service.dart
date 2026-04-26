import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const _themeKey = 'theme_mode';
  final SharedPreferences _prefs;
  late ThemeMode _themeMode;

  ThemeService(this._prefs) {
    final isDark = _prefs.getBool(_themeKey);
    if (isDark == null) {
      _themeMode = ThemeMode.system;
    } else {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    }
  }

  ThemeMode get themeMode => _themeMode;

  void toggleTheme() {
    // If it's system, we default to toggling to the opposite of what is mostly expected, 
    // or just checking if it is dark.
    final isCurrentlyDark = _themeMode == ThemeMode.dark;
    _themeMode = isCurrentlyDark ? ThemeMode.light : ThemeMode.dark;
    _prefs.setBool(_themeKey, !isCurrentlyDark);
    notifyListeners();
  }

  void setTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    _prefs.setBool(_themeKey, isDark);
    notifyListeners();
  }
}
