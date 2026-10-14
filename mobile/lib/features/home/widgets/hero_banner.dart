import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/net_image.dart';
import '../../../data/models/models.dart';
import '../../../providers/app_providers.dart';
import '../../../router.dart';

const _heroHeight = 480.0;

/// Banner besar di puncak beranda: gambar penuh, gradasi ke latar, judul,
/// genre, tombol Play + My List, serta bilah ikon (logo, cari, notifikasi).
class HeroBanner extends ConsumerStatefulWidget {
  const HeroBanner({super.key, required this.items});

  final List<AnimeSummary> items;

  @override
  ConsumerState<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends ConsumerState<HeroBanner> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startAutoplay();
  }

  void _startAutoplay() {
    _timer?.cancel();
    if (widget.items.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void didUpdateWidget(covariant HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) _startAutoplay();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox(height: _heroHeight, child: _HeroTopBar());
    }

    return SizedBox(
      height: _heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _HeroSlide(anime: widget.items[i]),
          ),
          const _HeroTopBar(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: i == _index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index ? AppColors.accent : Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSlide extends ConsumerWidget {
  const _HeroSlide({required this.anime});

  final AnimeSummary anime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(libraryProvider.select((l) => l.isFavorite(anime.key)));
    final genres = anime.genres.isNotEmpty
        ? anime.genres.take(4).join(', ')
        : [
            if (anime.type != null) anime.type!,
            if (yearOf(anime.releaseDate) != null) yearOf(anime.releaseDate)!,
            if (cleanScore(anime.score) != null) '★ ${cleanScore(anime.score)}',
          ].join(' • ');

    return Stack(
      fit: StackFit.expand,
      children: [
        NetImage(url: anime.image, provider: anime.provider),
        // Vignette atas + gradasi bawah ke warna latar
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.35, 0.72, 1.0],
              colors: [
                Color(0x990D0D12),
                Colors.transparent,
                Color(0xCC0D0D12),
                AppColors.bg,
              ],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                anime.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
                ),
              ),
              if (genres.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  genres,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  PrimaryButton(
                    label: 'Play',
                    icon: Icons.play_circle_fill_rounded,
                    onPressed: () => context.push(AppRoutes.detailOf(anime.provider, anime.id)),
                  ),
                  const SizedBox(width: 10),
                  OutlineButtonPill(
                    label: isFav ? 'Tersimpan' : 'My List',
                    icon: isFav ? Icons.check_rounded : Icons.add_rounded,
                    active: isFav,
                    onPressed: () async {
                      final added = await ref.read(libraryProvider.notifier).toggleFavorite(anime);
                      if (context.mounted) {
                        showToast(
                          context,
                          added ? 'Ditambahkan ke Daftarku' : 'Dihapus dari Daftarku',
                          icon: added ? Icons.bookmark_added_rounded : Icons.bookmark_remove_rounded,
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bilah atas transparan: logo kiri, ikon cari & notifikasi kanan.
class _HeroTopBar extends StatelessWidget {
  const _HeroTopBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 14, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppLogo(size: 38),
            const SizedBox(width: 10),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                AppConfig.brandName,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -0.3),
              ),
            ),
            const Spacer(),
            GlassIconButton(
              icon: Icons.search_rounded,
              tooltip: 'Cari',
              onPressed: () => context.push(AppRoutes.search),
            ),
            const SizedBox(width: 6),
            GlassIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Episode baru',
              onPressed: () => context.go(AppRoutes.calendar),
            ),
          ],
        ),
      ),
    );
  }
}

class HeroBannerSkeleton extends StatelessWidget {
  const HeroBannerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: _heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SkeletonBox(radius: 0),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, AppColors.bg],
              ),
            ),
          ),
          _HeroTopBar(),
          Positioned(
            left: 20,
            right: 20,
            bottom: 36,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 240, height: 26),
                SizedBox(height: 10),
                SkeletonBox(width: 180, height: 14),
                SizedBox(height: 18),
                Row(
                  children: [
                    SkeletonBox(width: 110, height: 42, radius: 999),
                    SizedBox(width: 10),
                    SkeletonBox(width: 110, height: 42, radius: 999),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HeroErrorBanner extends StatelessWidget {
  const HeroErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _heroHeight * 0.85,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A0A10), AppColors.bg],
              ),
            ),
          ),
          const _HeroTopBar(),
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: ErrorView(message: message, onRetry: onRetry, onSettings: onSettings),
          ),
        ],
      ),
    );
  }
}
