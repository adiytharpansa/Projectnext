import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../theme/app_theme.dart';

/// Gambar jaringan dengan placeholder gelap. Mencoba URL asli dulu (dengan
/// Referer situs sumber); bila gagal — umumnya karena proteksi hotlink —
/// otomatis dimuat ulang lewat `/api/proxy` backend.
class NetImage extends ConsumerWidget {
  const NetImage({
    super.key,
    required this.url,
    this.provider,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  final String url;
  final String? provider;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (url.isEmpty) return _fallback();

    final referer = provider == null
        ? null
        : ref.watch(providerBaseUrlsProvider)[provider!];
    final api = ref.watch(apiClientProvider);

    Widget image = CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      httpHeaders: referer == null ? null : {'Referer': referer},
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, __) => _placeholder(),
      errorWidget: (_, __, ___) => CachedNetworkImage(
        imageUrl: api.proxyUrl(url, referer: referer),
        fit: fit,
        width: width,
        height: height,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _fallback(),
      ),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Widget _placeholder() => Container(
        width: width,
        height: height,
        color: AppColors.surfaceAlt,
      );

  Widget _fallback() => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: borderRadius,
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.movie_outlined, color: AppColors.muted),
      );
}
