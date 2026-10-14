import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/net_image.dart';
import '../../core/widgets/poster_card.dart';
import '../../data/models/models.dart';
import '../../providers/app_providers.dart';
import '../../router.dart';

/// Daftarku: tab Favorit (grid poster) dan Riwayat (progres tonton).
class MyListScreen extends ConsumerWidget {
  const MyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Daftarku', style: TextStyle(fontWeight: FontWeight.w700)),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.muted,
            indicatorColor: AppColors.accent,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            tabs: [
              Tab(text: 'Favorit (${lib.watchlist.length})'),
              Tab(text: 'Riwayat (${lib.history.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _FavoritesTab(items: lib.watchlist),
            _HistoryTab(items: lib.history),
          ],
        ),
      ),
    );
  }
}

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab({required this.items});

  final List<AnimeSummary> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyView(
        icon: Icons.bookmark_border_rounded,
        title: 'Belum ada favorit',
        subtitle: 'Tekan "My List" di beranda atau ikon hati di halaman detail.',
        actionLabel: 'Cari anime',
        onAction: () => context.push(AppRoutes.search),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 0.56,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final a = items[i];
        return LayoutBuilder(
          builder: (context, c) => PosterCard(
            anime: a,
            width: c.maxWidth,
            height: c.maxWidth * 1.42,
            showTitle: true,
            onTap: () => context.push(AppRoutes.detailOf(a.provider, a.id)),
          ),
        );
      },
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.items});

  final List<HistoryEntry> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return EmptyView(
        icon: Icons.history_rounded,
        title: 'Belum ada riwayat',
        subtitle: 'Episode yang kamu tonton akan muncul di sini beserta progresnya.',
        actionLabel: 'Jelajahi',
        onAction: () => context.go(AppRoutes.home),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      itemCount: items.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == items.length) {
          return Center(
            child: TextButton.icon(
              onPressed: () => ref.read(libraryProvider.notifier).clearHistory(),
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.muted),
              label: const Text('Hapus semua riwayat', style: TextStyle(color: AppColors.muted)),
            ),
          );
        }
        final h = items[i];
        return Dismissible(
          key: ValueKey(h.key),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: AppColors.accentSoft),
          ),
          onDismissed: (_) => ref.read(libraryProvider.notifier).removeHistory(h.key),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push(AppRoutes.watchOf(
              provider: h.provider,
              episodeId: h.episodeId,
              animeId: h.animeId,
              animeTitle: h.animeTitle,
              image: h.image,
              episodeNumber: h.episodeNumber,
            )),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  NetImage(
                    url: h.image,
                    provider: h.provider,
                    width: 56,
                    height: 78,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.animeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Episode ${h.episodeNumber} • ${relativeDate(h.updatedAt)}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: h.progress,
                            minHeight: 4,
                            backgroundColor: AppColors.surfaceAlt,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          h.isFinished
                              ? 'Selesai'
                              : '${formatDuration(Duration(milliseconds: h.positionMs))} / ${formatDuration(Duration(milliseconds: h.durationMs))}',
                          style: TextStyle(
                            color: h.isFinished ? AppColors.success : AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Detail',
                    onPressed: () => context.push(AppRoutes.detailOf(h.provider, h.animeId)),
                    icon: const Icon(Icons.info_outline_rounded, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
