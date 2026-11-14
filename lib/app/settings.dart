import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/providers.dart';

// Preferências do app. O tema é único (escuro/ Aurora), então não há mais
// seletor de tema: apenas idioma e o aviso simulado de novidades.
class AppSettings {
  const AppSettings({
    this.locale = const Locale('pt', 'BR'),
    this.notifications = true,
  });

  final Locale locale;
  final bool notifications;

  bool get isEnglish => locale.languageCode == 'en';

  AppSettings copyWith({
    Locale? locale,
    bool? notifications,
  }) =>
      AppSettings(
        locale: locale ?? this.locale,
        notifications: notifications ?? this.notifications,
      );
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  static const String _localeKey = 'settings.locale';
  static const String _notificationsKey = 'settings.notifications';

  @override
  AppSettings build() {
    final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
    final String rawLocale = prefs.getString(_localeKey) ?? 'pt';
    return AppSettings(
      locale: rawLocale == 'en' ? const Locale('en') : const Locale('pt', 'BR'),
      notifications: prefs.getBool(_notificationsKey) ?? true,
    );
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
