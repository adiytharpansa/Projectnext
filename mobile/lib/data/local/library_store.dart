import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Satu entri riwayat tonton (per anime disimpan episode terakhir).
class HistoryEntry {
  const HistoryEntry({
    required this.provider,
    required this.animeId,
    required this.animeTitle,
    required this.image,
    required this.episodeId,
    required this.episodeNumber,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    this.watchedEpisodeIds = const [],
  });

  final String provider;
  final String animeId;
  final String animeTitle;
  final String image;
  final String episodeId;
  final int episodeNumber;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  /// Semua episode yang pernah dibuka untuk anime ini.
  final List<String> watchedEpisodeIds;

  String get key => '$provider/$animeId';

  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();

  bool get isFinished => durationMs > 0 && progress >= 0.95;

  HistoryEntry copyWith({
    String? episodeId,
    int? episodeNumber,
    int? positionMs,
    int? durationMs,
    DateTime? updatedAt,
    List<String>? watchedEpisodeIds,
    String? image,
    String? animeTitle,
  }) =>
      HistoryEntry(
        provider: provider,
        animeId: animeId,
        animeTitle: animeTitle ?? this.animeTitle,
        image: image ?? this.image,
        episodeId: episodeId ?? this.episodeId,
        episodeNumber: episodeNumber ?? this.episodeNumber,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        updatedAt: updatedAt ?? this.updatedAt,
        watchedEpisodeIds: watchedEpisodeIds ?? this.watchedEpisodeIds,
      );

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'animeId': animeId,
        'animeTitle': animeTitle,
        'image': image,
        'episodeId': episodeId,
        'episodeNumber': episodeNumber,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'watchedEpisodeIds': watchedEpisodeIds,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        provider: jsonStr(j['provider']),
        animeId: jsonStr(j['animeId']),
        animeTitle: jsonStr(j['animeTitle']),
        image: jsonStr(j['image']),
        episodeId: jsonStr(j['episodeId']),
        episodeNumber: jsonInt(j['episodeNumber']),
        positionMs: jsonInt(j['positionMs']),
        durationMs: jsonInt(j['durationMs']),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(jsonInt(j['updatedAt'])),
        watchedEpisodeIds: jsonStrList(j['watchedEpisodeIds']),
      );
}

/// Tautan unduhan yang disimpan pengguna (dibuka lewat browser/pengelola unduhan).
class SavedDownload {
  const SavedDownload({
    required this.provider,
    required this.animeId,
    required this.animeTitle,
    required this.image,
    required this.episodeId,
    required this.episodeNumber,
    required this.resolution,
    required this.server,
    required this.url,
    required this.savedAt,
    this.format,
  });

  final String provider;
  final String animeId;
  final String animeTitle;
  final String image;
  final String episodeId;
  final int episodeNumber;
  final String resolution;
  final String server;
  final String url;
  final DateTime savedAt;
  final String? format;

  bool get isMagnet => url.startsWith('magnet:');

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'animeId': animeId,
        'animeTitle': animeTitle,
        'image': image,
        'episodeId': episodeId,
        'episodeNumber': episodeNumber,
        'resolution': resolution,
        'server': server,
        'url': url,
        'savedAt': savedAt.millisecondsSinceEpoch,
        if (format != null) 'format': format,
      };

  factory SavedDownload.fromJson(Map<String, dynamic> j) => SavedDownload(
        provider: jsonStr(j['provider']),
        animeId: jsonStr(j['animeId']),
        animeTitle: jsonStr(j['animeTitle']),
        image: jsonStr(j['image']),
        episodeId: jsonStr(j['episodeId']),
        episodeNumber: jsonInt(j['episodeNumber']),
        resolution: jsonStr(j['resolution'], 'default'),
        server: jsonStr(j['server'], 'server'),
        url: jsonStr(j['url']),
        savedAt: DateTime.fromMillisecondsSinceEpoch(jsonInt(j['savedAt'])),
        format: jsonStrOrNull(j['format']),
      );
}

class LibraryState {
  const LibraryState({
    this.watchlist = const [],
    this.history = const [],
    this.downloads = const [],
  });

  final List<AnimeSummary> watchlist;

  /// Terurut dari yang paling baru ditonton.
  final List<HistoryEntry> history;
  final List<SavedDownload> downloads;

  bool isFavorite(String key) => watchlist.any((a) => a.key == key);

  HistoryEntry? historyFor(String provider, String animeId) {
    for (final h in history) {
      if (h.provider == provider && h.animeId == animeId) return h;
    }
    return null;
  }

  HistoryEntry? historyForEpisode(String provider, String episodeId) {
    for (final h in history) {
      if (h.provider == provider && h.episodeId == episodeId) return h;
    }
    return null;
  }

  Set<String> watchedEpisodeIds(String provider, String animeId) {
    final h = historyFor(provider, animeId);
    if (h == null) return const {};
    return {...h.watchedEpisodeIds, h.episodeId};
  }

  bool hasDownload(String url) => downloads.any((d) => d.url == url);

  LibraryState copyWith({
    List<AnimeSummary>? watchlist,
    List<HistoryEntry>? history,
    List<SavedDownload>? downloads,
  }) =>
      LibraryState(
        watchlist: watchlist ?? this.watchlist,
        history: history ?? this.history,
        downloads: downloads ?? this.downloads,
      );
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  LibraryNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static const _kWatchlist = 'library.watchlist';
  static const _kHistory = 'library.history';
  static const _kDownloads = 'library.downloads';
  static const _maxHistory = 100;

  static List<Map<String, dynamic>> _readList(SharedPreferences p, String k) {
    final raw = p.getString(k);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return jsonMapList(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }

  static LibraryState _load(SharedPreferences p) {
    final history = _readList(p, _kHistory).map(HistoryEntry.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return LibraryState(
      watchlist: _readList(p, _kWatchlist)
          .map((e) => AnimeSummary.fromJson(e))
          .toList(),
      history: history,
      downloads:
          _readList(p, _kDownloads).map(SavedDownload.fromJson).toList(),
    );
  }

  Future<void> _persist() async {
    await _prefs.setString(
        _kWatchlist, jsonEncode(state.watchlist.map((e) => e.toJson()).toList()));
    await _prefs.setString(
        _kHistory, jsonEncode(state.history.map((e) => e.toJson()).toList()));
    await _prefs.setString(_kDownloads,
        jsonEncode(state.downloads.map((e) => e.toJson()).toList()));
  }

  // ───────────── favorit ─────────────

  Future<bool> toggleFavorite(AnimeSummary anime) async {
    final exists = state.isFavorite(anime.key);
    final list = exists
        ? state.watchlist.where((a) => a.key != anime.key).toList()
        : [anime, ...state.watchlist];
    state = state.copyWith(watchlist: list);
    await _persist();
    return !exists;
  }

  // ───────────── riwayat ─────────────

  Future<void> saveProgress({
    required String provider,
    required String animeId,
    required String animeTitle,
    required String image,
    required String episodeId,
    required int episodeNumber,
    required int positionMs,
    required int durationMs,
  }) async {
    final existing = state.historyFor(provider, animeId);
    final watched = <String>{
      if (existing != null) ...existing.watchedEpisodeIds,
      if (existing != null) existing.episodeId,
      episodeId,
    }.toList();

    final entry = HistoryEntry(
      provider: provider,
      animeId: animeId,
      animeTitle: animeTitle.isNotEmpty ? animeTitle : (existing?.animeTitle ?? ''),
      image: image.isNotEmpty ? image : (existing?.image ?? ''),
      episodeId: episodeId,
      episodeNumber: episodeNumber,
      positionMs: positionMs,
      durationMs: durationMs,
      updatedAt: DateTime.now(),
      watchedEpisodeIds: watched,
    );

    final others =
        state.history.where((h) => h.key != entry.key).take(_maxHistory - 1);
    state = state.copyWith(history: [entry, ...others]);
    await _persist();
  }

  Future<void> removeHistory(String key) async {
    state = state.copyWith(
        history: state.history.where((h) => h.key != key).toList());
    await _persist();
  }

  Future<void> clearHistory() async {
    state = state.copyWith(history: const []);
    await _persist();
  }

  // ───────────── unduhan ─────────────

  Future<void> addDownload(SavedDownload d) async {
    if (state.hasDownload(d.url)) return;
    state = state.copyWith(downloads: [d, ...state.downloads]);
    await _persist();
  }

  Future<void> removeDownload(String url) async {
    state = state.copyWith(
        downloads: state.downloads.where((d) => d.url != url).toList());
    await _persist();
  }

  Future<void> clearDownloads() async {
    state = state.copyWith(downloads: const []);
    await _persist();
  }
}
