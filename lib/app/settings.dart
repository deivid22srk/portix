import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.locale = const Locale('pt', 'BR'),
    this.notifications = true,
  });

  final ThemeMode themeMode;
  final Locale locale;
  final bool notifications;

  bool get isEnglish => locale.languageCode == 'en';

  AppSettings copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    bool? notifications,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
        notifications: notifications ?? this.notifications,
      );
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  static const String _themeKey = 'settings.theme';
  static const String _localeKey = 'settings.locale';
  static const String _notificationsKey = 'settings.notifications';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final String rawTheme = prefs.getString(_themeKey) ?? 'dark';
    final String rawLocale = prefs.getString(_localeKey) ?? 'pt';
    return AppSettings(
      themeMode: _themeFrom(rawTheme),
      locale: rawLocale == 'en' ? const Locale('en') : const Locale('pt', 'BR'),
      notifications: prefs.getBool(_notificationsKey) ?? true,
    );
  }

  static ThemeMode _themeFrom(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    unawaited(ref.read(sharedPreferencesProvider).setString(_themeKey, mode.name));
  }

  void setLocale(Locale locale) {
    state = state.copyWith(locale: locale);
    unawaited(
      ref.read(sharedPreferencesProvider).setString(_localeKey, locale.languageCode),
    );
  }

  void setNotifications(bool enabled) {
    state = state.copyWith(notifications: enabled);
    unawaited(ref.read(sharedPreferencesProvider).setBool(_notificationsKey, enabled));
  }
}
