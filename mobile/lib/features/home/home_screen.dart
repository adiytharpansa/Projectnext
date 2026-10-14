import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/poster_card.dart';
import '../../providers/app_providers.dart';
import '../../router.dart';
import 'widgets/hero_banner.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider);
    final library = ref.watch(libraryProvider);

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surfaceAlt,
        onRefresh: () async {
          ref.invalidate(homeFeedProvider);
          ref.invalidate(latestEpisodesProvider);
          try {
            await ref.read(homeFeedProvider.future);
          } catch (_) {
            // Error sudah ditampilkan oleh banner hero.
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // ── Hero ──
            SliverToBoxAdapter(
              child: feed.when(
                data: (f) => HeroBanner(items: f.heroes),
                loading: () => const HeroBannerSkeleton(),
                error: (e, _) => HeroErrorBanner(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(homeFeedProvider),
                  onSettings: () => context.go(AppRoutes.profile),
                ),
              ),
            ),

            // ── Lanjutkan menonton ──
            if (library.history.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Lanjutkan Menonton',
                  onAction: () => context.go(AppRoutes.myList),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 178,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: math.min(library.history.length, 10),
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final h = library.history[i];
                      return EpisodeCard(
                        title: h.animeTitle,
                        image: h.image,
                        provider: h.provider,
                        subtitle:
                            'Episode ${h.episodeNumber} • ${formatDuration(Duration(milliseconds: h.positionMs))}',
                        progress: h.progress,
                        badge: 'EP ${h.episodeNumber}',
                        onTap: () => context.push(AppRoutes.watchOf(
                          provider: h.provider,
                          episodeId: h.episodeId,
                          animeId: h.animeId,
                          animeTitle: h.animeTitle,
                          image: h.image,
                          episodeNumber: h.episodeNumber,
                        )),
                      );
                    },
                  ),
                ),
              ),
            ],

            // ── Top hits ──
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Top Hits Anime',
                onAction: () => context.push(AppRoutes.search),
              ),
            ),
            SliverToBoxAdapter(
              child: feed.when(
                data: (f) => f.topHits.isEmpty
                    ? const _InlineNotice(
                        icon: Icons.search_off_rounded,
                        text:
                            'Belum ada hasil dari provider ini. Coba ganti provider default di Profil.',
                      )
                    : SizedBox(
                        height: 210,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: f.topHits.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, i) {
                            final a = f.topHits[i];
                            return PosterCard(
                              anime: a,
                              rank: i + 1,
                              width: 150,
                              height: 210,
                              onTap: () => context.push(
                                  AppRoutes.detailOf(a.provider, a.id)),
                            );
                          },
                        ),
                      ),
                loading: () => const PosterRowSkeleton(height: 210, width: 150),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            // ── Episode baru dari Daftarku ──
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Episode Baru',
                onAction: () => context.go(AppRoutes.calendar),
              ),
            ),
            SliverToBoxAdapter(child: _LatestEpisodesRow(hasWatchlist: library.watchlist.isNotEmpty)),

            // ── Favorit ──
            if (library.watchlist.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Favorit Kamu',
                  onAction: () => context.go(AppRoutes.myList),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 236,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: math.min(library.watchlist.length, 12),
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final a = library.watchlist[i];
                      return PosterCard(
                        anime: a,
                        width: 130,
                        height: 185,
                        showTitle: true,
                        onTap: () =>
                            context.push(AppRoutes.detailOf(a.provider, a.id)),
                      );
                    },
                  ),
                ),
              ),
            ],

            // ── Provider ──
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'Jelajahi Sumber'),
            ),
            const SliverToBoxAdapter(child: _ProviderChips()),

            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }
}

class _LatestEpisodesRow extends ConsumerWidget {
  const _LatestEpisodesRow({required this.hasWatchlist});

  final bool hasWatchlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasWatchlist) {
      return _InlineNotice(
        icon: Icons.bookmark_add_outlined,
        text: 'Tambahkan anime ke Daftarku untuk memantau episode terbarunya di sini.',
        actionLabel: 'Cari anime',
        onAction: () => context.push(AppRoutes.search),
      );
    }
    final latest = ref.watch(latestEpisodesProvider);
    return latest.when(
      data: (items) => items.isEmpty
          ? const _InlineNotice(
              icon: Icons.hourglass_empty_rounded,
              text: 'Belum ada data episode untuk judul di Daftarku.',
            )
          : SizedBox(
              height: 178,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final it = items[i];
                  return EpisodeCard(
                    title: it.anime.title,
                    image: it.anime.image,
                    provider: it.anime.provider,
                    subtitle: it.episode.date ?? (it.info.status ?? 'Episode ${it.episode.number}'),
                    badge: 'EP ${it.episode.number}',
                    onTap: () => context.push(AppRoutes.watchOf(
                      provider: it.anime.provider,
                      episodeId: it.episode.id,
                      animeId: it.anime.id,
                      animeTitle: it.anime.title,
                      image: it.anime.image,
                      episodeNumber: it.episode.number,
                    )),
                  );
                },
              ),
            ),
      loading: () => const SizedBox(
        height: 178,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              SkeletonBox(width: 220, height: 124, radius: 14),
              SizedBox(width: 12),
              SkeletonBox(width: 220, height: 124, radius: 14),
            ],
          ),
        ),
      ),
      error: (e, _) => _InlineNotice(icon: Icons.cloud_off_rounded, text: e.toString()),
    );
  }
}

class _ProviderChips extends ConsumerWidget {
  const _ProviderChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(providersProvider).valueOrNull;
    final ids = ref.watch(providerIdsProvider);
    final defaultProvider = ref.watch(settingsProvider.select((s) => s.defaultProvider));

    String nameOf(String id) {
      if (providers == null) return id;
      for (final p in providers) {
        if (p.id == id) return p.name;
      }
      return id;
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: ids.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final id = ids[i];
          final isDefault = id == defaultProvider;
          return ActionChip(
            avatar: Icon(
              isDefault ? Icons.star_rounded : Icons.public_rounded,
              size: 16,
              color: isDefault ? AppColors.warning : AppColors.muted,
            ),
            label: Text(nameOf(id)),
            onPressed: () => context.push(AppRoutes.searchWith(provider: id)),
          );
        },
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!,
                    style: const TextStyle(color: AppColors.accentSoft, fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
