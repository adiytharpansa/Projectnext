import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/net_image.dart';
import '../../core/widgets/poster_card.dart';
import '../../data/models/models.dart';
import '../../providers/app_providers.dart';
import '../../router.dart';
import '../download/download_sheet.dart';

/// Halaman detail: gambar besar + tombol putar, judul & aksi (unduh, bagikan,
/// favorit), chip info, sinopsis, grid episode, rekomendasi.
class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({super.key, required this.provider, required this.id});

  final String provider;
  final String id;

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  bool _expanded = false;
  bool _newestFirst = false;
  int _rangeIndex = -1; // -1 = belum dipilih (ikuti riwayat)

  static const _rangeSize = 50;

  AnimeRef get _ref => (provider: widget.provider, id: widget.id);

  void _play(AnimeInfo info, Episode ep) {
    context.push(AppRoutes.watchOf(
      provider: info.provider,
      episodeId: ep.id,
      animeId: info.id,
      animeTitle: info.title,
      image: info.image,
      episodeNumber: ep.number,
    ));
  }

  /// Episode yang dilanjutkan: terakhir ditonton (bila belum selesai) →
  /// episode berikutnya → episode pertama.
  Episode? _resumeEpisode(AnimeInfo info, LibraryState lib) {
    final h = lib.historyFor(info.provider, info.id);
    if (h == null) return info.firstEpisode;
    final last = info.episodeById(h.episodeId);
    if (last == null) return info.firstEpisode;
    if (!h.isFinished) return last;
    return info.neighbour(last.id, 1) ?? last;
  }

  Future<void> _share(AnimeInfo info) async {
    final text = '${info.title}\n${info.url}';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showToast(context, 'Tautan disalin ke papan klip', icon: Icons.link_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final infoAsync = ref.watch(animeInfoProvider(_ref));
    final lib = ref.watch(libraryProvider);

    return Scaffold(
      body: infoAsync.when(
        loading: () => const _DetailSkeleton(),
        error: (e, _) => SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () => context.pop(),
                ),
              ),
              Expanded(
                child: ErrorView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(animeInfoProvider(_ref)),
                  onSettings: () => context.go(AppRoutes.profile),
                ),
              ),
            ],
          ),
        ),
        data: (info) => _buildContent(context, info, lib),
      ),
      bottomNavigationBar: infoAsync.maybeWhen(
        data: (info) => _BottomBar(
          info: info,
          resume: _resumeEpisode(info, lib),
          history: lib.historyFor(info.provider, info.id),
          onPlay: (ep) => _play(info, ep),
          onDownload: (ep) => showDownloadSheet(
            context,
            provider: info.provider,
            animeId: info.id,
            animeTitle: info.title,
            image: info.image,
            episodeId: ep.id,
            episodeNumber: ep.number,
          ),
        ),
        orElse: () => null,
      ),
    );
  }

  Widget _buildContent(BuildContext context, AnimeInfo info, LibraryState lib) {
    final isFav = lib.isFavorite(info.key);
    final watched = lib.watchedEpisodeIds(info.provider, info.id);
    final history = lib.historyFor(info.provider, info.id);
    final resume = _resumeEpisode(info, lib);
    final year = yearOf(info.releaseDate);
    final score = cleanScore(info.score);
    final episodes = info.episodesAscending;

    // Rentang episode (untuk judul panjang)
    final rangeCount = (episodes.length / _rangeSize).ceil();
    var rangeIndex = _rangeIndex;
    if (rangeIndex < 0 || rangeIndex >= rangeCount) {
      rangeIndex = 0;
      if (history != null) {
        final idx = episodes.indexWhere((e) => e.id == history.episodeId);
        if (idx >= 0) rangeIndex = idx ~/ _rangeSize;
      }
    }
    final rangeStart = rangeIndex * _rangeSize;
    final rangeEnd = math.min(rangeStart + _rangeSize, episodes.length);
    var visible = episodes.sublist(rangeStart, rangeEnd);
    if (_newestFirst) visible = visible.reversed.toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          expandedHeight: 330,
          pinned: true,
          stretch: true,
          backgroundColor: AppColors.bg,
          leading: Padding(
            padding: const EdgeInsets.all(6),
            child: GlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 18,
              onPressed: () => context.pop(),
            ),
          ),
          actions: [
            GlassIconButton(
              icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFav ? AppColors.accentSoft : Colors.white,
              iconSize: 20,
              onPressed: () async {
                final added = await ref
                    .read(libraryProvider.notifier)
                    .toggleFavorite(info.toSummary());
                if (context.mounted) {
                  showToast(context, added ? 'Ditambahkan ke Daftarku' : 'Dihapus dari Daftarku');
                }
              },
            ),
            const SizedBox(width: 12),
          ],
          flexibleSpace: FlexibleSpaceBar(
            stretchModes: const [StretchMode.zoomBackground],
            background: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(url: info.image, provider: info.provider),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.5, 1.0],
                      colors: [Color(0x880D0D12), Color(0x330D0D12), AppColors.bg],
                    ),
                  ),
                ),
                if (resume != null)
                  Center(
                    child: GestureDetector(
                      onTap: () => _play(info, resume),
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.7), width: 1.5),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, size: 40, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ── judul + aksi ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      info.title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ActionIcon(
                    icon: Icons.download_outlined,
                    tooltip: 'Unduh',
                    onTap: resume == null
                        ? null
                        : () => showDownloadSheet(
                              context,
                              provider: info.provider,
                              animeId: info.id,
                              animeTitle: info.title,
                              image: info.image,
                              episodeId: resume.id,
                              episodeNumber: resume.number,
                            ),
                  ),
                  _ActionIcon(
                    icon: Icons.share_outlined,
                    tooltip: 'Bagikan',
                    onTap: () => _share(info),
                  ),
                  _ActionIcon(
                    icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isFav ? AppColors.accentSoft : Colors.white,
                    tooltip: 'Favorit',
                    onTap: () => ref.read(libraryProvider.notifier).toggleFavorite(info.toSummary()),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── chip info ──
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  InfoChip('${info.totalEpisodes > 0 ? info.totalEpisodes : episodes.length} EPS',
                      highlight: true),
                  if (year != null) InfoChip(year),
                  if (info.type != null) InfoChip(info.type!),
                  if (info.status != null) InfoChip(info.status!, icon: Icons.schedule_rounded),
                  if (score != null) InfoChip(score, icon: Icons.star_rounded),
                  InfoChip(info.provider.toUpperCase(), icon: Icons.public_rounded),
                ],
              ),
              if (info.genres.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final g in info.genres) InfoChip(g)],
                ),
              ],

              // ── sinopsis ──
              if (info.description != null && info.description!.isNotEmpty) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    alignment: Alignment.topCenter,
                    child: Text.rich(
                      TextSpan(
                        text: _expanded
                            ? info.description!.trim()
                            : truncate(info.description!.trim(), 180),
                        children: [
                          if (info.description!.trim().length > 180)
                            TextSpan(
                              text: _expanded ? '  Lebih sedikit' : '  Selengkapnya',
                              style: const TextStyle(
                                color: AppColors.accentSoft,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.55),
                    ),
                  ),
                ),
              ],

              // ── episode ──
              const SizedBox(height: 22),
              Row(
                children: [
                  Text(
                    'Episode (${episodes.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                  const Spacer(),
                  if (info.batchUrl != null)
                    TextButton.icon(
                      onPressed: () => launchUrl(Uri.parse(info.batchUrl!),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.archive_outlined, size: 16, color: AppColors.accentSoft),
                      label: const Text('Batch',
                          style: TextStyle(color: AppColors.accentSoft, fontSize: 12.5)),
                    ),
                  TextButton.icon(
                    onPressed: () => setState(() => _newestFirst = !_newestFirst),
                    icon: Icon(
                      _newestFirst ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                      size: 16,
                      color: AppColors.accentSoft,
                    ),
                    label: Text(
                      _newestFirst ? 'Terbaru' : 'Terlama',
                      style: const TextStyle(color: AppColors.accentSoft, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              if (rangeCount > 1) ...[
                const SizedBox(height: 4),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: rangeCount,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final start = i * _rangeSize + 1;
                      final end = math.min((i + 1) * _rangeSize, episodes.length);
                      final selected = i == rangeIndex;
                      return ChoiceChip(
                        label: Text('$start–$end'),
                        selected: selected,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : AppColors.muted,
                          fontSize: 12,
                        ),
                        onSelected: (_) => setState(() => _rangeIndex = i),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (episodes.isEmpty)
                const EmptyView(
                  icon: Icons.tv_off_rounded,
                  title: 'Belum ada episode',
                  subtitle: 'Provider ini tidak menyediakan daftar episode untuk judul ini.',
                  compact: true,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final ep in visible)
                      _EpisodeChip(
                        episode: ep,
                        current: history?.episodeId == ep.id,
                        watched: watched.contains(ep.id),
                        onTap: () => _play(info, ep),
                        onLongPress: () => showDownloadSheet(
                          context,
                          provider: info.provider,
                          animeId: info.id,
                          animeTitle: info.title,
                          image: info.image,
                          episodeId: ep.id,
                          episodeNumber: ep.number,
                        ),
                      ),
                  ],
                ),
              if (episodes.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Tekan lama nomor episode untuk melihat tautan unduhan.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                  ),
                ),

              // ── info tambahan ──
              if (info.otherNames.isNotEmpty || info.studios.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text('Informasi', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                const SizedBox(height: 8),
                if (info.otherNames.isNotEmpty)
                  _InfoRow(label: 'Nama lain', value: info.otherNames.join(', ')),
                if (info.studios.isNotEmpty)
                  _InfoRow(label: 'Studio', value: info.studios.join(', ')),
                if (info.releaseDate != null)
                  _InfoRow(label: 'Rilis', value: info.releaseDate!),
              ],
            ]),
          ),
        ),

        // ── rekomendasi ──
        SliverToBoxAdapter(child: _Recommendations(exclude: info.key)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: onTap == null ? AppColors.muted : color, size: 24),
    );
  }
}

class _EpisodeChip extends StatelessWidget {
  const _EpisodeChip({
    required this.episode,
    required this.current,
    required this.watched,
    required this.onTap,
    required this.onLongPress,
  });

  final Episode episode;
  final bool current;
  final bool watched;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final bg = current
        ? AppColors.accent
        : watched
            ? AppColors.accent.withOpacity(0.18)
            : AppColors.surfaceAlt;
    final fg = current
        ? Colors.white
        : watched
            ? AppColors.accentSoft
            : Colors.white;

    return Tooltip(
      message: episode.title ?? 'Episode ${episode.number}',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 54,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: current ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            episode.label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _Recommendations extends ConsumerWidget {
  const _Recommendations({required this.exclude});

  final String exclude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider).valueOrNull;
    final items = (feed?.topHits ?? const <AnimeSummary>[])
        .where((a) => a.key != exclude)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Rekomendasi untukmu'),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final a = items[i];
              return PosterCard(
                anime: a,
                width: 112,
                height: 160,
                onTap: () => context.pushReplacement(AppRoutes.detailOf(a.provider, a.id)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.info,
    required this.resume,
    required this.history,
    required this.onPlay,
    required this.onDownload,
  });

  final AnimeInfo info;
  final Episode? resume;
  final HistoryEntry? history;
  final ValueChanged<Episode> onPlay;
  final ValueChanged<Episode> onDownload;

  @override
  Widget build(BuildContext context) {
    final ep = resume;
    final label = ep == null
        ? 'Tidak ada episode'
        : (history != null && history!.episodeId == ep.id && !history!.isFinished)
            ? 'Lanjutkan EP ${ep.number}'
            : 'Putar EP ${ep.number}';

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: PrimaryButton(
              label: label,
              icon: Icons.play_arrow_rounded,
              expanded: true,
              onPressed: ep == null ? null : () => onPlay(ep),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: OutlineButtonPill(
              label: 'Unduh',
              icon: Icons.download_rounded,
              expanded: true,
              onPressed: ep == null ? null : () => onDownload(ep),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            const SkeletonBox(height: 330, radius: 0),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 240, height: 24),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      SkeletonBox(width: 60, height: 24, radius: 8),
                      SizedBox(width: 6),
                      SkeletonBox(width: 60, height: 24, radius: 8),
                      SizedBox(width: 6),
                      SkeletonBox(width: 60, height: 24, radius: 8),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const SkeletonBox(height: 14),
                  const SizedBox(height: 8),
                  const SkeletonBox(height: 14),
                  const SizedBox(height: 8),
                  const SkeletonBox(width: 200, height: 14),
                  const SizedBox(height: 26),
                  const SkeletonBox(width: 120, height: 20),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      12,
                      (_) => const SkeletonBox(width: 54, height: 42, radius: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: GlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 18,
              onPressed: () => context.pop(),
            ),
          ),
        ),
      ],
    );
  }
}
