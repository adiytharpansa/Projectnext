import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../providers/app_providers.dart';
import '../../router.dart';
import '../download/download_sheet.dart';
import 'player_controls.dart';

/// Pemutar video layar penuh (lanskap). Alur:
///  1. ambil `watch` dari backend → pilih sumber terbaik (hls > mp4)
///  2. HLS diputar lewat `/api/proxy/m3u8` (Referer disuntik, segmen di-rewrite)
///     MP4 diputar langsung + header; bila gagal, otomatis dicoba via proxy
///  3. progres disimpan tiap 5 detik → "Lanjutkan Menonton"
///  4. selesai → otomatis lanjut episode berikutnya (bisa dimatikan di Profil)
class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({
    super.key,
    required this.provider,
    required this.episodeId,
    required this.animeId,
    this.animeTitle,
    this.image,
    this.episodeNumber,
  });

  final String provider;
  final String episodeId;
  final String animeId;
  final String? animeTitle;
  final String? image;
  final int? episodeNumber;

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  VideoPlayerController? _controller;
  WatchData? _data;
  StreamSource? _source;
  SubtitleTrack? _subtitle;
  bool _viaProxy = false;
  bool _initializing = false;
  bool _embedOnly = false;
  bool _completed = false;
  String? _error;

  bool _controlsVisible = true;
  bool _locked = false;
  double _speed = 1.0;
  Timer? _hideTimer;
  Timer? _progressTimer;

  late final LibraryNotifier _library;

  /// Salinan info anime terakhir yang termuat — dipakai juga saat dispose
  /// (tidak boleh menyentuh `ref` di sana).
  AnimeInfo? _infoCache;

  EpisodeRef get _epRef => (provider: widget.provider, episodeId: widget.episodeId);
  AnimeRef get _animeRef => (provider: widget.provider, id: widget.animeId);

  @override
  void initState() {
    super.initState();
    _library = ref.read(libraryProvider.notifier);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
    _scheduleHide();
  }

  @override
  void dispose() {
    _saveProgress();
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    final c = _controller;
    _controller = null;
    c?.removeListener(_onTick);
    c?.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  // ───────────── sumber & pemutar ─────────────

  void _setupFromData(WatchData data) {
    _data = data;
    final best = data.bestSource;
    if (best == null || !best.isPlayable) {
      setState(() {
        _embedOnly = true;
        _initializing = false;
      });
      return;
    }
    _subtitle = data.subtitles.isNotEmpty ? data.subtitles.first : null;
    // Preferensi Profil: MP4 selalu lewat proxy (HLS memang selalu via proxy).
    final preferProxy = ref.read(settingsProvider).mp4ViaProxy;
    _loadSource(data, best, viaProxy: preferProxy && !best.isHls);
  }

  Future<void> _loadSource(WatchData data, StreamSource source, {bool viaProxy = false}) async {
    final old = _controller;
    setState(() {
      _source = source;
      _viaProxy = viaProxy;
      _error = null;
      _embedOnly = false;
      _completed = false;
      _controller = null;
      _initializing = true;
    });
    old?.removeListener(_onTick);
    await old?.dispose();

    final api = ref.read(apiClientProvider);
    final referer = data.referer;
    final useProxy = source.isHls || viaProxy;

    final String url;
    final Map<String, String> headers;
    if (useProxy) {
      url = api.proxyUrl(source.url, referer: referer);
      headers = const {};
    } else {
      url = source.url;
      headers = {...data.headers};
      if (referer != null && !headers.keys.any((k) => k.toLowerCase() == 'referer')) {
        headers['Referer'] = referer;
      }
    }

    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers,
      formatHint: source.isHls ? VideoFormat.hls : null,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );

    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      // Lanjutkan dari posisi terakhir bila belum selesai
      final h = ref.read(libraryProvider).historyForEpisode(widget.provider, widget.episodeId);
      if (h != null && h.positionMs > 10000 && !h.isFinished) {
        await c.seekTo(Duration(milliseconds: h.positionMs));
      }
      await c.setPlaybackSpeed(_speed);
      c.addListener(_onTick);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _initializing = false;
      });
      if (_subtitle != null) _applySubtitle(c, _subtitle);
      _scheduleHide();
    } catch (e) {
      await c.dispose();
      if (!mounted) return;
      // MP4 langsung gagal (umumnya Referer/CORS) → coba lewat proxy sekali.
      if (!useProxy) {
        _loadSource(data, source, viaProxy: true);
        return;
      }
      setState(() {
        _initializing = false;
        _error = 'Gagal memutar sumber ${source.label}.\n$e';
      });
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError && _error == null) {
      setState(() => _error = v.errorDescription ?? 'Pemutar mengalami kesalahan.');
      return;
    }
    if (!_completed &&
        v.isInitialized &&
        v.duration > Duration.zero &&
        !v.isPlaying &&
        v.position >= v.duration - const Duration(milliseconds: 800)) {
      _completed = true;
      _onCompleted();
    }
  }

  void _onCompleted() {
    _saveProgress(finished: true);
    final autoplay = ref.read(settingsProvider).autoplayNext;
    final next = _neighbour(1);
    if (autoplay && next != null) {
      _goToEpisode(next);
    } else {
      setState(() => _controlsVisible = true);
    }
  }

  Future<void> _applySubtitle(VideoPlayerController c, SubtitleTrack? track) async {
    if (track == null) {
      await c.setClosedCaptionFile(null);
      return;
    }
    try {
      final text = await ref
          .read(apiClientProvider)
          .fetchText(track.url, referer: _data?.referer);
      final ClosedCaptionFile file = text.trimLeft().startsWith('WEBVTT')
          ? WebVTTCaptionFile(text)
          : SubRipCaptionFile(text);
      if (_controller == c) await c.setClosedCaptionFile(Future.value(file));
    } catch (_) {
      if (mounted) showToast(context, 'Subtitle gagal dimuat');
    }
  }

  // ───────────── progres & navigasi episode ─────────────

  AnimeInfo? get _info => _infoCache;

  Episode? _neighbour(int offset) => _info?.neighbour(widget.episodeId, offset);

  int get _episodeNumber =>
      widget.episodeNumber ?? _info?.episodeById(widget.episodeId)?.number ?? 0;

  void _saveProgress({bool finished = false}) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final dur = c.value.duration.inMilliseconds;
    if (dur <= 0) return;
    _library.saveProgress(
      provider: widget.provider,
      animeId: widget.animeId,
      animeTitle: widget.animeTitle ?? _info?.title ?? '',
      image: widget.image ?? _info?.image ?? '',
      episodeId: widget.episodeId,
      episodeNumber: _episodeNumber,
      positionMs: finished ? dur : c.value.position.inMilliseconds,
      durationMs: dur,
    );
  }

  void _goToEpisode(Episode ep) {
    _saveProgress();
    final info = _info;
    context.pushReplacement(AppRoutes.watchOf(
      provider: widget.provider,
      episodeId: ep.id,
      animeId: widget.animeId,
      animeTitle: widget.animeTitle ?? info?.title,
      image: widget.image ?? info?.image,
      episodeNumber: ep.number,
    ));
  }

  // ───────────── kontrol ─────────────

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (_controller?.value.isPlaying ?? false) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _playPause() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      if (_completed) {
        _completed = false;
        c.seekTo(Duration.zero);
      }
      c.play();
    }
    setState(() {});
    _scheduleHide();
  }

  void _seekRelative(Duration delta) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    var target = c.value.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > c.value.duration) target = c.value.duration;
    c.seekTo(target);
    _scheduleHide();
  }

  void _seekTo(Duration d) {
    _controller?.seekTo(d);
    _scheduleHide();
  }

  Future<void> _pickSpeed() async {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final chosen = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => _SheetList<double>(
        title: 'Kecepatan putar',
        items: speeds,
        selected: _speed,
        label: (s) => s == 1.0 ? 'Normal (1.0x)' : '${s}x',
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _speed = chosen);
    await _controller?.setPlaybackSpeed(chosen);
  }

  Future<void> _pickSource() async {
    final data = _data;
    if (data == null) return;
    final result = await showModalBottomSheet<_SourceChoice>(
      context: context,
      builder: (ctx) => _SourceSheet(
        data: data,
        current: _source,
        viaProxy: _viaProxy,
      ),
    );
    if (result == null || !mounted) return;
    if (result.openExternal != null) {
      final ok = await openExternal(result.openExternal!);
      if (!ok && mounted) showToast(context, 'Tidak bisa membuka tautan');
      return;
    }
    if (result.source != null) {
      _loadSource(data, result.source!, viaProxy: result.viaProxy);
    }
  }

  Future<void> _pickSubtitle() async {
    final data = _data;
    final c = _controller;
    if (data == null || c == null || data.subtitles.isEmpty) return;
    final items = <SubtitleTrack?>[null, ...data.subtitles];
    final chosen = await showModalBottomSheet<_Wrapped<SubtitleTrack?>>(
      context: context,
      builder: (ctx) => _SheetList<_Wrapped<SubtitleTrack?>>(
        title: 'Subtitle',
        items: items.map((t) => _Wrapped<SubtitleTrack?>(t)).toList(),
        selected: _Wrapped<SubtitleTrack?>(_subtitle),
        label: (w) => w.value == null ? 'Nonaktif' : w.value!.display,
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _subtitle = chosen.value);
    await _applySubtitle(c, chosen.value);
  }

  Future<void> _showEpisodes() async {
    final info = _info;
    if (info == null) {
      showToast(context, 'Daftar episode belum termuat');
      return;
    }
    final chosen = await showModalBottomSheet<Episode>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EpisodeSheet(info: info, currentId: widget.episodeId),
    );
    if (chosen != null && mounted && chosen.id != widget.episodeId) {
      _goToEpisode(chosen);
    }
  }

  Future<void> _showMore() async {
    final data = _data;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded, color: AppColors.accentSoft),
              title: const Text('Tautan unduhan episode ini'),
              onTap: () => Navigator.of(ctx).pop('download'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_browser_rounded),
              title: const Text('Buka di browser'),
              subtitle: Text(
                data?.embedUrl ?? _source?.url ?? '-',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              onTap: () => Navigator.of(ctx).pop('browser'),
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Muat ulang sumber'),
              onTap: () => Navigator.of(ctx).pop('reload'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'download':
        await showDownloadSheet(
          context,
          provider: widget.provider,
          animeId: widget.animeId,
          animeTitle: widget.animeTitle ?? _info?.title ?? '',
          image: widget.image ?? _info?.image ?? '',
          episodeId: widget.episodeId,
          episodeNumber: _episodeNumber,
          initialGroups: data?.download,
        );
      case 'browser':
        final url = data?.embedUrl ?? _source?.url;
        if (url != null) await openExternal(url);
      case 'reload':
        ref.invalidate(watchDataProvider(_epRef));
        setState(() {
          _source = null;
          _error = null;
          _embedOnly = false;
        });
    }
  }

  // ───────────── build ─────────────

  @override
  Widget build(BuildContext context) {
    final watchAsync = ref.watch(watchDataProvider(_epRef));
    final infoAsync = ref.watch(animeInfoProvider(_animeRef));
    _infoCache = infoAsync.valueOrNull ?? _infoCache;

    // Data tiba → siapkan pemutar sekali (setelah frame ini).
    final data = watchAsync.valueOrNull;
    if (data != null && _source == null && !_initializing && !_embedOnly && _error == null) {
      _initializing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setupFromData(data);
      });
    }

    final title = widget.animeTitle ?? infoAsync.valueOrNull?.title ?? 'Memutar';
    final epLabel = 'Episode $_episodeNumber'
        '${_source != null ? ' • ${_source!.label}${_viaProxy ? ' (proxy)' : ''}' : ''}';

    Widget body;
    if (watchAsync.hasError && data == null) {
      body = _MessagePanel(
        icon: Icons.cloud_off_rounded,
        title: 'Gagal mengambil sumber video',
        message: watchAsync.error.toString(),
        actions: [
          PrimaryButton(
            label: 'Coba lagi',
            icon: Icons.refresh_rounded,
            onPressed: () => ref.invalidate(watchDataProvider(_epRef)),
          ),
          OutlineButtonPill(label: 'Kembali', onPressed: () => context.pop()),
        ],
      );
    } else if (_embedOnly) {
      body = _EmbedPanel(
        data: data,
        onOpen: (url) => openExternal(url),
        onDownload: () => _showMore(),
        onBack: () => context.pop(),
      );
    } else if (_error != null) {
      body = _MessagePanel(
        icon: Icons.error_outline_rounded,
        title: 'Tidak bisa memutar',
        message: _error!,
        actions: [
          PrimaryButton(
            label: 'Coba lagi',
            icon: Icons.refresh_rounded,
            onPressed: () {
              final d = _data;
              final s = _source;
              if (d != null && s != null) _loadSource(d, s, viaProxy: _viaProxy);
            },
          ),
          OutlineButtonPill(
            label: 'Server lain',
            icon: Icons.dns_outlined,
            onPressed: _pickSource,
          ),
          OutlineButtonPill(label: 'Kembali', onPressed: () => context.pop()),
        ],
      );
    } else if (_controller == null) {
      body = const _LoadingPanel();
    } else {
      final c = _controller!;
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: _locked
            ? null
            : (d) {
                final w = MediaQuery.of(context).size.width;
                _seekRelative(Duration(seconds: d.globalPosition.dx < w / 2 ? -10 : 10));
              },
        onDoubleTap: () {},
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
                child: VideoPlayer(c),
              ),
            ),
            // Subtitle
            Positioned(
              left: 24,
              right: 24,
              bottom: _controlsVisible ? 96 : 28,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (_, v, __) => v.caption.text.isEmpty
                    ? const SizedBox.shrink()
                    : ClosedCaption(
                        text: v.caption.text,
                        textStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          backgroundColor: Colors.black54,
                        ),
                      ),
              ),
            ),
            PlayerControls(
              controller: c,
              visible: _controlsVisible,
              locked: _locked,
              title: title,
              episodeLabel: epLabel,
              qualityLabel: (_source?.quality.isEmpty ?? true) ? 'AUTO' : _source!.quality.toUpperCase(),
              speed: _speed,
              hasSubtitles: (_data?.subtitles.isNotEmpty) ?? false,
              subtitleOn: _subtitle != null,
              hasPrev: _neighbour(-1) != null,
              hasNext: _neighbour(1) != null,
              onBack: () => context.pop(),
              onPlayPause: _playPause,
              onSeekRelative: _seekRelative,
              onSeekTo: _seekTo,
              onToggleLock: () {
                setState(() {
                  _locked = !_locked;
                  _controlsVisible = true;
                });
                _scheduleHide();
              },
              onSpeed: _pickSpeed,
              onQuality: _pickSource,
              onSubtitles: _pickSubtitle,
              onPrev: () {
                final p = _neighbour(-1);
                if (p != null) _goToEpisode(p);
              },
              onNext: () {
                final n = _neighbour(1);
                if (n != null) _goToEpisode(n);
              },
              onEpisodes: _showEpisodes,
              onMore: _showMore,
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: !_locked,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: body,
      ),
    );
  }
}

// ───────────── panel-panel pendukung ─────────────

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.accent),
              SizedBox(height: 14),
              Text('Memuat sumber video…', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        SafeArea(
          child: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: AppColors.accentSoft),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sumber hanya tersedia sebagai pemutar embed pihak ketiga.
class _EmbedPanel extends StatelessWidget {
  const _EmbedPanel({
    required this.data,
    required this.onOpen,
    required this.onDownload,
    required this.onBack,
  });

  final WatchData? data;
  final ValueChanged<String> onOpen;
  final VoidCallback onDownload;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final primary = d?.embedUrl ?? (d != null && d.sources.isNotEmpty ? d.sources.first.url : null);
    final servers = <NamedServer>[
      if (d != null) ...d.servers,
      if (d != null)
        for (final s in d.sources)
          if (s.isEmbed || s.type == 'embed') NamedServer(name: s.server ?? s.quality, url: s.url),
    ];

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.web_asset_rounded, size: 40, color: AppColors.warning),
              const SizedBox(height: 10),
              const Text(
                'Sumber ini berupa pemutar embed',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Backend belum bisa mengekstrak tautan langsung dari server ini. '
                'Buka di browser, atau gunakan tautan unduhan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final s in servers.take(8))
                    ActionChip(
                      avatar: const Icon(Icons.open_in_new_rounded, size: 14),
                      label: Text(s.name),
                      onPressed: () => onOpen(s.url),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (primary != null)
                    PrimaryButton(
                      label: 'Buka di browser',
                      icon: Icons.open_in_browser_rounded,
                      onPressed: () => onOpen(primary),
                    ),
                  OutlineButtonPill(
                    label: 'Unduhan',
                    icon: Icons.download_rounded,
                    onPressed: onDownload,
                  ),
                  OutlineButtonPill(label: 'Kembali', onPressed: onBack),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────── lembar pilihan ─────────────

class _Wrapped<T> {
  const _Wrapped(this.value);
  final T value;

  @override
  bool operator ==(Object other) => other is _Wrapped<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class _SheetList<T> extends StatelessWidget {
  const _SheetList({
    required this.title,
    required this.items,
    required this.selected,
    required this.label,
  });

  final String title;
  final List<T> items;
  final T selected;
  final String Function(T) label;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final it in items)
                  ListTile(
                    dense: true,
                    title: Text(label(it)),
                    trailing: it == selected
                        ? const Icon(Icons.check_rounded, color: AppColors.accent)
                        : null,
                    onTap: () => Navigator.of(context).pop(it),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceChoice {
  const _SourceChoice({this.source, this.viaProxy = false, this.openExternal});
  final StreamSource? source;
  final bool viaProxy;
  final String? openExternal;
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.data, required this.current, required this.viaProxy});

  final WatchData data;
  final StreamSource? current;
  final bool viaProxy;

  @override
  Widget build(BuildContext context) {
    final playable = data.playableSources;
    final embeds = data.sources.where((s) => !s.isPlayable).toList();

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Kualitas & server', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          if (playable.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('Tidak ada sumber langsung.', style: TextStyle(color: AppColors.muted)),
            ),
          for (final s in playable)
            ListTile(
              dense: true,
              leading: Icon(
                s.isHls ? Icons.stream_rounded : Icons.movie_outlined,
                color: s == current ? AppColors.accent : AppColors.muted,
              ),
              title: Text(s.label),
              subtitle: Text(
                s.isHls ? 'HLS • lewat proxy' : 'MP4 • langsung',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              trailing: s == current
                  ? const Icon(Icons.check_rounded, color: AppColors.accent)
                  : null,
              onTap: () => Navigator.of(context).pop(_SourceChoice(source: s)),
            ),
          if (current != null && !current!.isHls)
            ListTile(
              dense: true,
              leading: const Icon(Icons.shield_outlined, color: AppColors.muted),
              title: Text(viaProxy ? 'Putar langsung (tanpa proxy)' : 'Putar lewat proxy'),
              subtitle: const Text(
                'Coba bila video tidak mau dimuat',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              onTap: () => Navigator.of(context).pop(
                _SourceChoice(source: current, viaProxy: !viaProxy),
              ),
            ),
          if (embeds.isNotEmpty || data.servers.isNotEmpty) ...[
            const Divider(height: 16),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Server embed (buka di browser)',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
            for (final s in embeds)
              ListTile(
                dense: true,
                leading: const Icon(Icons.open_in_new_rounded, color: AppColors.muted),
                title: Text(s.server ?? s.quality),
                onTap: () => Navigator.of(context).pop(_SourceChoice(openExternal: s.url)),
              ),
            for (final s in data.servers)
              ListTile(
                dense: true,
                leading: const Icon(Icons.open_in_new_rounded, color: AppColors.muted),
                title: Text(s.name),
                onTap: () => Navigator.of(context).pop(_SourceChoice(openExternal: s.url)),
              ),
          ],
        ],
      ),
    );
  }
}

class _EpisodeSheet extends StatelessWidget {
  const _EpisodeSheet({required this.info, required this.currentId});

  final AnimeInfo info;
  final String currentId;

  @override
  Widget build(BuildContext context) {
    final eps = info.episodesAscending;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(
                '${info.title} • ${eps.length} episode',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 64,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.3,
                ),
                itemCount: eps.length,
                itemBuilder: (context, i) {
                  final ep = eps[i];
                  final current = ep.id == currentId;
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(ep),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: current ? AppColors.accent : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: current ? AppColors.accent : AppColors.border),
                      ),
                      child: Text(ep.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
