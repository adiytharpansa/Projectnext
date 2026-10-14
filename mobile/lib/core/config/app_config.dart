import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Konfigurasi statis aplikasi. Nilai yang bisa diubah pengguna (URL server,
/// provider default, dsb.) ada di [AppSettings], bukan di sini.
class AppConfig {
  AppConfig._();

  static const brandName = 'Anilab';
  static const tagline = 'Nonton & unduh anime favoritmu — streaming online.';
  static const version = '1.0.0';
  static const repoUrl = 'https://github.com/adiytharpansa/Projectnext';

  /// Provider yang dipakai bila daftar provider dari server belum termuat.
  static const defaultProvider = 'gogo';
  static const fallbackProviders = <String>[
    'gogo',
    'samehadaku',
    'gogoby',
    'crunchyroll',
    'iqiyi',
    'torrentio',
    'nyaa',
  ];

  /// Backend Projectnext belum punya endpoint "trending", jadi beranda
  /// dibangun dari pencarian judul-judul populer berikut (bisa diubah).
  static const topHitSeeds = <String>[
    'Demon Slayer',
    'Jujutsu Kaisen',
    'One Piece',
    'Attack on Titan',
    'Spy x Family',
    'Solo Leveling',
    'Frieren',
    'Naruto',
  ];

  /// Saran pencarian cepat di layar Cari.
  static const popularSearches = <String>[
    'Naruto',
    'One Piece',
    'Jujutsu Kaisen',
    'Frieren',
    'Solo Leveling',
    'Dandadan',
    'Bleach',
    'Chainsaw Man',
    'Blue Lock',
    'Oshi no Ko',
  ];

  /// Batas permintaan paralel ke server saat membangun beranda, agar situs
  /// sumber tidak membatasi (rate-limit) backend.
  static const homeFeedConcurrency = 3;

  /// Bisa dipaksa saat build: `flutter build web --dart-define=API_BASE_URL=https://api.contoh.com`
  static const _envApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Default alamat backend:
  ///  - `--dart-define=API_BASE_URL=…` bila diberikan;
  ///  - web → origin halaman (API di-proxy dari host yang sama);
  ///  - emulator Android → 10.0.2.2 (host); lainnya → localhost.
  /// Perangkat fisik: isi IP LAN / URL deploy di Profil.
  static String get defaultApiBaseUrl {
    if (_envApiBaseUrl.isNotEmpty) return _envApiBaseUrl;
    if (kIsWeb) return Uri.base.origin;
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://localhost:3000';
  }
}
