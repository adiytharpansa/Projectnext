/// Model data klien — cerminan kontrak backend Projectnext (`src/types.ts`).
/// Semua parser toleran terhadap field yang hilang / bertipe tak terduga,
/// karena data berasal dari scraping yang bentuknya bisa berubah.
library;

// ───────────────────────── helper parsing JSON ─────────────────────────

String jsonStr(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

String? jsonStrOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int jsonInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

bool jsonBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

List<String> jsonStrList(dynamic v) {
  if (v is! List) return const [];
  return v
      .map((e) => e?.toString().trim() ?? '')
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

List<Map<String, dynamic>> jsonMapList(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

Map<String, String> jsonStrMap(dynamic v) {
  if (v is! Map) return const {};
  return v.map((k, val) => MapEntry(k.toString(), val?.toString() ?? ''));
}

// ───────────────────────── provider ─────────────────────────

class ProviderMeta {
  const ProviderMeta({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.languages,
    required this.supports,
  });

  final String id;
  final String name;
  final String baseUrl;
  final List<String> languages;
  final List<String> supports;

  bool get canWatch => supports.contains('watch');
  bool get canDownload => supports.contains('download');

  factory ProviderMeta.fromJson(Map<String, dynamic> j) => ProviderMeta(
        id: jsonStr(j['id']),
        name: jsonStr(j['name'], jsonStr(j['id'])),
        baseUrl: jsonStr(j['baseUrl']),
        languages: jsonStrList(j['languages']),
        supports: jsonStrList(j['supports']),
      );
}

class ProviderError {
  const ProviderError({required this.provider, required this.message});
  final String provider;
  final String message;

  factory ProviderError.fromJson(Map<String, dynamic> j) => ProviderError(
        provider: jsonStr(j['provider']),
        message: jsonStr(j['message']),
      );
}

// ───────────────────────── anime ─────────────────────────

class AnimeSummary {
  const AnimeSummary({
    required this.provider,
    required this.id,
    required this.title,
    required this.url,
    required this.image,
    this.releaseDate,
    this.type,
    this.score,
    this.genres = const [],
    this.description,
  });

  final String provider;
  final String id;
  final String title;
  final String url;
  final String image;
  final String? releaseDate;
  final String? type;
  final String? score;
  final List<String> genres;
  final String? description;

  /// Kunci unik lintas provider, dipakai untuk favorit/riwayat.
  String get key => '$provider/$id';

  factory AnimeSummary.fromJson(Map<String, dynamic> j,
          {String? fallbackProvider}) =>
      AnimeSummary(
        provider: jsonStr(j['provider'], fallbackProvider ?? ''),
        id: jsonStr(j['id']),
        title: jsonStr(j['title'], 'Tanpa judul'),
        url: jsonStr(j['url']),
        image: jsonStr(j['image']),
        releaseDate: jsonStrOrNull(j['releaseDate']),
        type: jsonStrOrNull(j['type']),
        score: jsonStrOrNull(j['score']),
        genres: jsonStrList(j['genres']),
        description: jsonStrOrNull(j['description']),
      );

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'id': id,
        'title': title,
        'url': url,
        'image': image,
        if (releaseDate != null) 'releaseDate': releaseDate,
        if (type != null) 'type': type,
        if (score != null) 'score': score,
        if (genres.isNotEmpty) 'genres': genres,
        if (description != null) 'description': description,
      };
}

class Episode {
  const Episode({
    required this.id,
    required this.number,
    required this.url,
    this.title,
    this.date,
  });

  final String id;
  final int number;
  final String url;
  final String? title;
  final String? date;

  /// "01", "02", … "125" — label chip episode.
  String get label => number.toString().padLeft(2, '0');

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: jsonStr(j['id']),
        number: jsonInt(j['number']),
        url: jsonStr(j['url']),
        title: jsonStrOrNull(j['title']),
        date: jsonStrOrNull(j['date']),
      );
}

class AnimeInfo {
  const AnimeInfo({
    required this.provider,
    required this.id,
    required this.title,
    required this.url,
    required this.image,
    required this.totalEpisodes,
    required this.episodes,
    this.description,
    this.genres = const [],
    this.status,
    this.type,
    this.releaseDate,
    this.otherNames = const [],
    this.trailer,
    this.score,
    this.studios = const [],
    this.batchUrl,
  });

  final String provider;
  final String id;
  final String title;
  final String url;
  final String image;
  final int totalEpisodes;
  final List<Episode> episodes;
  final String? description;
  final List<String> genres;
  final String? status;
  final String? type;
  final String? releaseDate;
  final List<String> otherNames;
  final String? trailer;
  final String? score;
  final List<String> studios;
  final String? batchUrl;

  String get key => '$provider/$id';

  /// Episode terurut naik berdasarkan nomor (sumber kadang membalik urutan).
  List<Episode> get episodesAscending {
    final list = [...episodes];
    list.sort((a, b) => a.number.compareTo(b.number));
    return list;
  }

  Episode? get firstEpisode =>
      episodesAscending.isEmpty ? null : episodesAscending.first;

  Episode? get latestEpisode =>
      episodesAscending.isEmpty ? null : episodesAscending.last;

  Episode? episodeById(String episodeId) {
    for (final e in episodes) {
      if (e.id == episodeId) return e;
    }
    return null;
  }

  Episode? neighbour(String episodeId, int offset) {
    final asc = episodesAscending;
    final idx = asc.indexWhere((e) => e.id == episodeId);
    if (idx < 0) return null;
    final target = idx + offset;
    if (target < 0 || target >= asc.length) return null;
    return asc[target];
  }

  AnimeSummary toSummary() => AnimeSummary(
        provider: provider,
        id: id,
        title: title,
        url: url,
        image: image,
        releaseDate: releaseDate,
        type: type,
        score: score,
        genres: genres,
        description: description,
      );

  factory AnimeInfo.fromJson(Map<String, dynamic> j,
      {String? fallbackProvider}) {
    final episodes = jsonMapList(j['episodes']).map(Episode.fromJson).toList();
    return AnimeInfo(
      provider: jsonStr(j['provider'], fallbackProvider ?? ''),
      id: jsonStr(j['id']),
      title: jsonStr(j['title'], 'Tanpa judul'),
      url: jsonStr(j['url']),
      image: jsonStr(j['image']),
      totalEpisodes: jsonInt(j['totalEpisodes'], episodes.length),
      episodes: episodes,
      description: jsonStrOrNull(j['description']),
      genres: jsonStrList(j['genres']),
      status: jsonStrOrNull(j['status']),
      type: jsonStrOrNull(j['type']),
      releaseDate: jsonStrOrNull(j['releaseDate']),
      otherNames: jsonStrList(j['otherNames']),
      trailer: jsonStrOrNull(j['trailer']),
      score: jsonStrOrNull(j['score']),
      studios: jsonStrList(j['studios']),
      batchUrl: jsonStrOrNull(j['batchUrl']),
    );
  }
}

// ───────────────────────── streaming ─────────────────────────

class StreamSource {
  const StreamSource({
    required this.url,
    required this.type,
    required this.quality,
    this.isEmbed = false,
    this.server,
  });

  final String url;

  /// "hls" | "mp4" | "embed"
  final String type;
  final String quality;
  final bool isEmbed;
  final String? server;

  bool get isHls => type == 'hls' || url.contains('.m3u8');
  bool get isPlayable => !isEmbed && type != 'embed' && url.isNotEmpty;

  String get label {
    final q = quality.isEmpty ? 'auto' : quality;
    final s = server == null || server!.isEmpty ? '' : ' • ${server!}';
    return '${q.toUpperCase()}$s';
  }

  factory StreamSource.fromJson(Map<String, dynamic> j) => StreamSource(
        url: jsonStr(j['url']),
        type: jsonStr(j['type'], 'mp4').toLowerCase(),
        quality: jsonStr(j['quality'], 'auto'),
        isEmbed: jsonBool(j['isEmbed']),
        server: jsonStrOrNull(j['server']),
      );
}

class SubtitleTrack {
  const SubtitleTrack({required this.url, required this.lang, this.label});
  final String url;
  final String lang;
  final String? label;

  String get display => label ?? lang;

  factory SubtitleTrack.fromJson(Map<String, dynamic> j) => SubtitleTrack(
        url: jsonStr(j['url']),
        lang: jsonStr(j['lang'], 'sub'),
        label: jsonStrOrNull(j['label']),
      );
}

class NamedServer {
  const NamedServer({required this.name, required this.url});
  final String name;
  final String url;

  factory NamedServer.fromJson(Map<String, dynamic> j) => NamedServer(
        name: jsonStr(j['name'], 'server'),
        url: jsonStr(j['url']),
      );
}

class DownloadLink {
  const DownloadLink({required this.server, required this.url});
  final String server;
  final String url;

  bool get isMagnet => url.startsWith('magnet:');

  factory DownloadLink.fromJson(Map<String, dynamic> j) => DownloadLink(
        server: jsonStr(j['server'], 'server'),
        url: jsonStr(j['url']),
      );
}

class DownloadGroup {
  const DownloadGroup({
    required this.resolution,
    required this.links,
    this.format,
  });

  final String resolution;
  final List<DownloadLink> links;
  final String? format;

  String get title =>
      format == null || format!.isEmpty ? resolution : '$resolution • $format';

  factory DownloadGroup.fromJson(Map<String, dynamic> j) => DownloadGroup(
        resolution: jsonStr(j['resolution'], 'default'),
        format: jsonStrOrNull(j['format']),
        links: jsonMapList(j['links']).map(DownloadLink.fromJson).toList(),
      );
}

class WatchData {
  const WatchData({
    required this.provider,
    required this.episodeId,
    required this.sources,
    required this.subtitles,
    this.title,
    this.embedUrl,
    this.headers = const {},
    this.servers = const [],
    this.download = const [],
  });

  final String provider;
  final String episodeId;
  final String? title;
  final String? embedUrl;
  final Map<String, String> headers;
  final List<StreamSource> sources;
  final List<SubtitleTrack> subtitles;
  final List<NamedServer> servers;
  final List<DownloadGroup> download;

  /// Referer yang perlu disuntikkan saat memutar/mem-proxy stream.
  String? get referer {
    for (final k in headers.keys) {
      if (k.toLowerCase() == 'referer') return headers[k];
    }
    return embedUrl;
  }

  List<StreamSource> get playableSources =>
      sources.where((s) => s.isPlayable).toList();

  /// hls > mp4 > apa pun yang tersedia.
  StreamSource? get bestSource {
    final playable = playableSources;
    for (final s in playable) {
      if (s.isHls) return s;
    }
    if (playable.isNotEmpty) return playable.first;
    return sources.isEmpty ? null : sources.first;
  }

  factory WatchData.fromJson(Map<String, dynamic> j,
          {String? fallbackProvider}) =>
      WatchData(
        provider: jsonStr(j['provider'], fallbackProvider ?? ''),
        episodeId: jsonStr(j['episodeId']),
        title: jsonStrOrNull(j['title']),
        embedUrl: jsonStrOrNull(j['embedUrl']),
        headers: jsonStrMap(j['headers']),
        sources: jsonMapList(j['sources']).map(StreamSource.fromJson).toList(),
        subtitles:
            jsonMapList(j['subtitles']).map(SubtitleTrack.fromJson).toList(),
        servers: jsonMapList(j['servers']).map(NamedServer.fromJson).toList(),
        download:
            jsonMapList(j['download']).map(DownloadGroup.fromJson).toList(),
      );
}

class SearchResponse {
  const SearchResponse({
    required this.query,
    required this.results,
    this.errors = const [],
  });

  final String query;
  final List<AnimeSummary> results;
  final List<ProviderError> errors;

  int get count => results.length;

  factory SearchResponse.fromJson(Map<String, dynamic> j) => SearchResponse(
        query: jsonStr(j['query']),
        results: jsonMapList(j['results'])
            .map((e) => AnimeSummary.fromJson(e,
                fallbackProvider: jsonStrOrNull(j['provider'])))
            .toList(),
        errors: jsonMapList(j['errors']).map(ProviderError.fromJson).toList(),
      );
}
