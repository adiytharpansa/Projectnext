import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';

/// Pengaturan pengguna yang disimpan di perangkat.
class AppSettings {
  const AppSettings({
    required this.apiBaseUrl,
    required this.defaultProvider,
    required this.onboardingDone,
    required this.autoplayNext,
    required this.mp4ViaProxy,
    required this.displayName,
  });

  final String apiBaseUrl;
  final String defaultProvider;
  final bool onboardingDone;
  final bool autoplayNext;

  /// Putar MP4 lewat proxy backend (lebih kompatibel, lebih berat di server).
  final bool mp4ViaProxy;
  final String displayName;

  AppSettings copyWith({
    String? apiBaseUrl,
    String? defaultProvider,
    bool? onboardingDone,
    bool? autoplayNext,
    bool? mp4ViaProxy,
    String? displayName,
  }) =>
      AppSettings(
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        defaultProvider: defaultProvider ?? this.defaultProvider,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        autoplayNext: autoplayNext ?? this.autoplayNext,
        mp4ViaProxy: mp4ViaProxy ?? this.mp4ViaProxy,
        displayName: displayName ?? this.displayName,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static const _kApi = 'settings.apiBaseUrl';
  static const _kProvider = 'settings.defaultProvider';
  static const _kOnboarding = 'settings.onboardingDone';
  static const _kAutoplay = 'settings.autoplayNext';
  static const _kMp4Proxy = 'settings.mp4ViaProxy';
  static const _kName = 'settings.displayName';

  static AppSettings _load(SharedPreferences p) => AppSettings(
        apiBaseUrl: p.getString(_kApi) ?? AppConfig.defaultApiBaseUrl,
        defaultProvider: p.getString(_kProvider) ?? AppConfig.defaultProvider,
        onboardingDone: p.getBool(_kOnboarding) ?? false,
        autoplayNext: p.getBool(_kAutoplay) ?? true,
        mp4ViaProxy: p.getBool(_kMp4Proxy) ?? false,
        displayName: p.getString(_kName) ?? 'Tamu',
      );

  static String normalizeUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return AppConfig.defaultApiBaseUrl;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Future<void> setApiBaseUrl(String url) async {
    final clean = normalizeUrl(url);
    state = state.copyWith(apiBaseUrl: clean);
    await _prefs.setString(_kApi, clean);
  }

  Future<void> setDefaultProvider(String id) async {
    state = state.copyWith(defaultProvider: id);
    await _prefs.setString(_kProvider, id);
  }

  Future<void> setOnboardingDone(bool v) async {
    state = state.copyWith(onboardingDone: v);
    await _prefs.setBool(_kOnboarding, v);
  }

  Future<void> setAutoplayNext(bool v) async {
    state = state.copyWith(autoplayNext: v);
    await _prefs.setBool(_kAutoplay, v);
  }

  Future<void> setMp4ViaProxy(bool v) async {
    state = state.copyWith(mp4ViaProxy: v);
    await _prefs.setBool(_kMp4Proxy, v);
  }

  Future<void> setDisplayName(String name) async {
    final clean = name.trim().isEmpty ? 'Tamu' : name.trim();
    state = state.copyWith(displayName: clean);
    await _prefs.setString(_kName, clean);
  }
}
