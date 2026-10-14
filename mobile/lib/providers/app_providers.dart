import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../data/api/api_client.dart';
import '../data/local/library_store.dart';
import '../data/local/settings_store.dart';
import '../data/models/models.dart';

export '../data/local/library_store.dart';
export '../data/local/settings_store.dart';

// ───────────── infrastruktur ─────────────

/// Di-override di `main()` setelah SharedPreferences siap.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider belum di-override'),
);

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(ref.watch(sharedPreferencesProvider)),
);

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>(
  (ref) => LibraryNotifier(ref.watch(sharedPreferencesProvider)),
);

/// Klien API dibuat ulang otomatis saat URL server diubah di Profil.
final apiClientProvider = Provider<ApiClient>((ref) {
  final base = ref.watch(settingsProvider.select((s) => s.apiBaseUrl));
  return ApiClient(base);
});

// ───────────── data server ─────────────

final providersProvider = FutureProvider<List<ProviderMeta>>(
  (ref) => ref.watch(apiClientProvider).providers(),
);

/// provider id → base URL situs sumber (dipakai sebagai Referer gambar).
final providerBaseUrlsProvider = Provider<Map<String, String>>((ref) {
  final list = ref.watch(providersProvider).valueOrNull ?? const <ProviderMeta>[];
  return {for (final p in list) p.id: p.baseUrl};
});

/// Daftar id provider untuk filter: dari server, atau fallback statis.
final providerIdsProvider = Provider<List<String>>((ref) {
  final list = ref.watch(providersProvider).valueOrNull;
  if (list == null || list.isEmpty) return AppConfig.fallbackProviders;
  return list.map((p) => p.id).toList();
});

typedef AnimeRef = ({String provider, String id});
typedef EpisodeRef = ({String provider, String episodeId});
typedef SearchArgs = ({String query, String? provider});

final searchProvider =
    FutureProvider.autoDispose.family<SearchResponse, SearchArgs>(
  (ref, args) =>
      ref.watch(apiClientProvider).search(args.query, provider: args.provider),
);

/// Detail anime di-cache selama sesi (dipakai detail, player, kalender).
final animeInfoProvider = FutureProvider.family<AnimeInfo, AnimeRef>(
  (ref, r) => ref.watch(apiClientProvider).info(r.provider, r.id),
);

final watchDataProvider =
    FutureProvider.autoDispose.family<WatchData, EpisodeRef>(
  (ref, r) => ref.watch(apiClientProvider).watch(r.provider, r.episodeId),
);

final downloadGroupsProvider =
    FutureProvider.autoDispose.family<List<DownloadGroup>, EpisodeRef>(
  (ref, r) => ref.watch(apiClientProvider).downloads(r.provider, r.episodeId),
);

// ───────────── beranda ─────────────

class HomeFeed {
  const HomeFeed({required this.topHits, required this.errors});

  final List<AnimeSummary> topHits;
  final List<String> errors;

  List<AnimeSummary> get heroes => topHits.take(5).toList();
}

/// Jalankan [task] untuk tiap item dengan maksimal [limit] proses paralel.
Future<List<T>> mapLimited<S, T>(
  Iterable<S> items,
  int limit,
  Future<T> Function(S item) task,
) async {
  final list = items.toList();
  final results = List<T?>.filled(list.length, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= list.length) return;
      results[i] = await task(list[i]);
    }
  }

  final workers = List.generate(
    math.max(1, math.min(limit, list.isEmpty ? 1 : list.length)),
    (_) => worker(),
  );
  await Future.wait(workers);
  return results.cast<T>();
}

/// Beranda: cari judul-judul populer (lihat [AppConfig.topHitSeeds]) pada
/// provider default, ambil hasil teratas tiap judul.
final homeFeedProvider = FutureProvider<HomeFeed>((ref) async {
  final api = ref.watch(apiClientProvider);
  final provider = ref.watch(settingsProvider.select((s) => s.defaultProvider));
  final errors = <String>[];
  var networkFailures = 0;
  String? networkMessage;

  final hits = await mapLimited<String, AnimeSummary?>(
    AppConfig.topHitSeeds,
    AppConfig.homeFeedConcurrency,
    (seed) async {
      try {
        final res = await api.search(seed, provider: provider);
        return res.results.isEmpty ? null : res.results.first;
      } on ApiException catch (e) {
        if (e.isNetwork) {
          networkFailures++;
          networkMessage ??= e.message;
        }
        errors.add('$seed: ${e.message}');
        return null;
      } catch (e) {
        errors.add('$seed: $e');
        return null;
      }
    },
  );

  // Semua gagal karena koneksi → anggap server mati, tampilkan state error.
  if (networkFailures == AppConfig.topHitSeeds.length) {
    throw ApiException(0, networkMessage ?? 'Server API tidak terjangkau');
  }

  final seen = <String>{};
  final unique = <AnimeSummary>[];
  for (final h in hits) {
    if (h != null && seen.add(h.key)) unique.add(h);
  }
  return HomeFeed(topHits: unique, errors: errors);
});

// ───────────── episode terbaru dari Daftarku ─────────────

class LatestEpisode {
  const LatestEpisode({required this.anime, required this.info, required this.episode});

  final AnimeSummary anime;
  final AnimeInfo info;
  final Episode episode;
}

/// Untuk setiap judul di Daftarku, ambil episode terbarunya (maks. 12 judul).
final latestEpisodesProvider = FutureProvider<List<LatestEpisode>>((ref) async {
  final watchlist = ref.watch(libraryProvider.select((l) => l.watchlist));
  final targets = watchlist.take(12).toList();

  final items = await mapLimited<AnimeSummary, LatestEpisode?>(
    targets,
    AppConfig.homeFeedConcurrency,
    (anime) async {
      try {
        // `read` (bukan `watch`): dipanggil asinkron di dalam worker; cache
        // animeInfoProvider tetap dipakai bersama layar detail & pemutar.
        final info = await ref.read(
          animeInfoProvider((provider: anime.provider, id: anime.id)).future,
        );
        final ep = info.latestEpisode;
        if (ep == null) return null;
        return LatestEpisode(anime: anime, info: info, episode: ep);
      } catch (_) {
        return null;
      }
    },
  );
  return items.whereType<LatestEpisode>().toList();
});

/// Status koneksi server (dipakai Profil & onboarding).
final serverOnlineProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(apiClientProvider).health(),
);
