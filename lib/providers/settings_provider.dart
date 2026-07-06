import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;
  bool _fbCdnEnabled = false;
  bool _autoRotate = false;

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;
  bool get fbCdnEnabled => _fbCdnEnabled;
  bool get autoRotate => _autoRotate;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString('theme') ?? 'system';
    _themeMode = theme == 'light'
        ? ThemeMode.light
        : theme == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;
    final lang = prefs.getString('language');
    _locale = lang != null ? Locale(lang) : null;
    _fbCdnEnabled = prefs.getBool('fb_cdn') ?? false;
    _autoRotate = prefs.getBool('auto_rotate') ?? false;
  }

  Future<void> setAutoRotate(bool enabled) async {
    if (_autoRotate == enabled) return;
    _autoRotate = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_rotate', enabled);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme',
      mode == ThemeMode.light
          ? 'light'
          : mode == ThemeMode.dark
              ? 'dark'
              : 'system',
    );
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    if (_locale == locale) return;
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale != null) {
      await prefs.setString('language', locale.languageCode);
    } else {
      await prefs.remove('language');
    }
    notifyListeners();
  }

  Future<void> setFbCdn(bool enabled) async {
    if (_fbCdnEnabled == enabled) return;
    _fbCdnEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fb_cdn', enabled);
    notifyListeners();
  }
}
