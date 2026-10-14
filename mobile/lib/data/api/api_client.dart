import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/models.dart';

/// Error terstruktur dari API (atau kegagalan koneksi bila [status] == 0).
class ApiException implements Exception {
  const ApiException(this.status, this.message);

  final int status;
  final String message;

  bool get isNetwork => status == 0;

  @override
  String toString() => message;
}

/// Klien HTTP untuk backend Projectnext (`/api/v1/*` + `/api/proxy`).
class ApiClient {
  ApiClient(String baseUrl)
      : baseUrl = _normalize(baseUrl),
        _dio = Dio(
          BaseOptions(
            baseUrl: _normalize(baseUrl),
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 60),
            sendTimeout: const Duration(seconds: 15),
            headers: const {'Accept': 'application/json'},
            responseType: ResponseType.json,
            // Status non-2xx tetap dikembalikan agar pesan error API terbaca.
            validateStatus: (_) => true,
          ),
        );

  final String baseUrl;
  final Dio _dio;

  static String _normalize(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  // ───────────── inti ─────────────

  Future<T> _get<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(dynamic data) parse,
  }) async {
    Response<dynamic> res;
    try {
      res = await _dio.get<dynamic>(path, queryParameters: query);
    } on DioException catch (e) {
      throw ApiException(0, _describeNetworkError(e));
    }
    return _unwrap(res, parse);
  }

  Future<T> _post<T>(
    String path, {
    Object? body,
    required T Function(dynamic data) parse,
  }) async {
    Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>(path, data: body);
    } on DioException catch (e) {
      throw ApiException(0, _describeNetworkError(e));
    }
    return _unwrap(res, parse);
  }

  T _unwrap<T>(Response<dynamic> res, T Function(dynamic data) parse) {
    dynamic body = res.data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } catch (_) {
        body = null;
      }
    }
    final code = res.statusCode ?? 0;
    if (body is! Map) {
      throw ApiException(code, 'Respons API tidak valid (HTTP $code)');
    }
    final map = Map<String, dynamic>.from(body);
    if (code < 200 || code >= 300 || map['success'] == false) {
      throw ApiException(
        jsonInt(map['status'], code),
        jsonStrOrNull(map['message']) ?? 'Error API (HTTP $code)',
      );
    }
    return parse(map['data']);
  }

  String _describeNetworkError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Server API tidak merespons (timeout). Periksa alamat server: $baseUrl';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return 'Tidak dapat terhubung ke server API ($baseUrl). '
            'Pastikan backend berjalan dan alamatnya benar di Profil.';
      case DioExceptionType.badCertificate:
        return 'Sertifikat HTTPS server tidak valid.';
      case DioExceptionType.cancel:
        return 'Permintaan dibatalkan.';
      case DioExceptionType.badResponse:
        return 'Respons server tidak valid (HTTP ${e.response?.statusCode}).';
      // Tipe baru di versi Dio mendatang (mis. transformTimeout) jatuh ke sini.
      // ignore: unreachable_switch_default
      default:
        return 'Permintaan ke server API gagal: ${e.message ?? e.type.name}';
    }
  }

  Map<String, dynamic> _asMap(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

  // ───────────── endpoint ─────────────

  /// GET /api/health — true bila server hidup.
  Future<bool> health() async {
    try {
      final res = await _dio.get<dynamic>('/api/health');
      return res.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  /// GET /api/v1/providers
  Future<List<ProviderMeta>> providers() => _get(
        '/api/v1/providers',
        parse: (data) {
          final list = data is Map ? data['providers'] : data;
          return jsonMapList(list).map(ProviderMeta.fromJson).toList();
        },
      );

  /// GET /api/v1/anime/search?query=&provider=  (provider kosong = agregat)
  Future<SearchResponse> search(String query, {String? provider}) => _get(
        '/api/v1/anime/search',
        query: {
          'query': query,
          if (provider != null && provider.isNotEmpty) 'provider': provider,
        },
        parse: (data) => SearchResponse.fromJson(_asMap(data)),
      );

  /// GET /api/v1/anime/info?provider=&id=
  Future<AnimeInfo> info(String provider, String id) => _get(
        '/api/v1/anime/info',
        query: {'provider': provider, 'id': id},
        parse: (data) =>
            AnimeInfo.fromJson(_asMap(data), fallbackProvider: provider),
      );

  /// GET /api/v1/anime/watch?provider=&episodeId=
  Future<WatchData> watch(String provider, String episodeId) => _get(
        '/api/v1/anime/watch',
        query: {'provider': provider, 'episodeId': episodeId},
        parse: (data) =>
            WatchData.fromJson(_asMap(data), fallbackProvider: provider),
      );

  /// GET /api/v1/anime/download?provider=&episodeId=
  Future<List<DownloadGroup>> downloads(String provider, String episodeId) =>
      _get(
        '/api/v1/anime/download',
        query: {'provider': provider, 'episodeId': episodeId},
        parse: (data) => jsonMapList(_asMap(data)['groups'])
            .map(DownloadGroup.fromJson)
            .toList(),
      );

  /// POST /api/v1/debrid/unrestrict { magnet } — magnet → tautan HTTP.
  Future<Map<String, dynamic>> unrestrictMagnet(String magnet) => _post(
        '/api/v1/debrid/unrestrict',
        body: {'magnet': magnet},
        parse: _asMap,
      );

  /// Ambil teks mentah (mis. file subtitle) lewat proxy backend.
  Future<String> fetchText(String url, {String? referer}) async {
    try {
      final res = await _dio.get<String>(
        proxyUrl(url, referer: referer),
        options: Options(responseType: ResponseType.plain),
      );
      if ((res.statusCode ?? 0) >= 400) {
        throw ApiException(res.statusCode ?? 0, 'Gagal mengambil $url');
      }
      return res.data ?? '';
    } on DioException catch (e) {
      throw ApiException(0, _describeNetworkError(e));
    }
  }

  // ───────────── proxy ─────────────

  /// URL anti-gagal untuk media:
  ///  - `.m3u8` → `/api/proxy/m3u8` (rewrite segmen + suntik Referer)
  ///  - lainnya (mp4/ts/vtt/gambar) → `/api/proxy`
  String proxyUrl(String raw, {String? referer}) {
    final isHls = raw.contains('.m3u8');
    final path = isHls ? '/api/proxy/m3u8' : '/api/proxy';
    final query = Uri(queryParameters: {
      'url': raw,
      if (referer != null && referer.isNotEmpty) 'referer': referer,
    }).query;
    return '$baseUrl$path?$query';
  }
}
