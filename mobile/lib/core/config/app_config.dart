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

  /// Emulator Android mengakses host lewat 10.0.2.2; simulator iOS & desktop
  /// bisa langsung ke localhost. Perangkat fisik: isi IP LAN di Profil.
  static String get defaultApiBaseUrl {
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://localhost:3000';
  }
}
