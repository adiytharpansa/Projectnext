import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'common.dart';
import 'net_image.dart';

/// Kartu poster vertikal (dipakai di grid Daftarku, hasil pencarian populer,
/// rekomendasi). Opsional: nomor peringkat besar ala "Top Hits".
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.anime,
    this.onTap,
    this.rank,
    this.width = 140,
    this.height = 200,
    this.showTitle = false,
    this.badge,
  });

  final AnimeSummary anime;
  final VoidCallback? onTap;
  final int? rank;
  final double width;
  final double height;
  final bool showTitle;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final year = yearOf(anime.releaseDate);
    final typeLabel = anime.type ?? year;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(
                    url: anime.image,
                    provider: anime.provider,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  // Gradasi bawah agar angka/judul terbaca
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.5, 1],
                        colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (typeLabel != null)
                          MiniBadge(
                            typeLabel.toUpperCase(),
                            color: Colors.black.withOpacity(0.55),
                          )
                        else
                          const SizedBox.shrink(),
                        MiniBadge(badge ?? 'HD'),
                      ],
                    ),
                  ),
                  if (rank != null)
                    Positioned(
                      left: 10,
                      bottom: 2,
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 60,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 12),
                            const Shadow(color: AppColors.accent, offset: Offset(2, 2)),
                          ],
                        ),
                      ),
                    ),
                  if (anime.score != null && cleanScore(anime.score) != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: MiniBadge(
                        cleanScore(anime.score)!,
                        icon: Icons.star_rounded,
                        color: Colors.black.withOpacity(0.55),
                        textColor: AppColors.warning,
                      ),
                    ),
                ],
              ),
            ),
            if (showTitle) ...[
              const SizedBox(height: 8),
              Text(
                anime.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kartu lanskap 16:9 dengan progres (Lanjutkan Menonton / Episode Baru).
class EpisodeCard extends StatelessWidget {
  const EpisodeCard({
    super.key,
    required this.title,
    required this.image,
    required this.provider,
    required this.subtitle,
    this.progress,
    this.badge,
    this.onTap,
    this.width = 220,
  });

  final String title;
  final String image;
  final String provider;
  final String subtitle;
  final double? progress;
  final String? badge;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(
                    url: image,
                    provider: provider,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                      ),
                    ),
                  ),
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded,
                        color: Colors.white, size: 40),
                  ),
                  if (badge != null)
                    Positioned(top: 8, left: 8, child: MiniBadge(badge!)),
                  if (progress != null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress!.clamp(0.0, 1.0).toDouble(),
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
