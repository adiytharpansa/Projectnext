import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../providers/app_providers.dart';

/// Buka tautan di aplikasi eksternal (browser / pengelola unduhan / klien
/// torrent). Mengembalikan false bila tidak ada aplikasi yang bisa menangani.
Future<bool> openExternal(String url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

Future<void> copyToClipboard(BuildContext context, String text, {String? label}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, label ?? 'Disalin ke papan klip', icon: Icons.copy_rounded);
}

/// Lembar bawah tautan unduhan satu episode, dikelompokkan per resolusi.
Future<void> showDownloadSheet(
  BuildContext context, {
  required String provider,
  required String animeId,
  required String animeTitle,
  required String image,
  required String episodeId,
  required int episodeNumber,
  List<DownloadGroup>? initialGroups,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (context, controller) => DownloadSheet(
        provider: provider,
        animeId: animeId,
        animeTitle: animeTitle,
        image: image,
        episodeId: episodeId,
        episodeNumber: episodeNumber,
        initialGroups: initialGroups,
        scrollController: controller,
      ),
    ),
  );
}

class DownloadSheet extends ConsumerWidget {
  const DownloadSheet({
    super.key,
    required this.provider,
    required this.animeId,
    required this.animeTitle,
    required this.image,
    required this.episodeId,
    required this.episodeNumber,
    required this.scrollController,
    this.initialGroups,
  });

  final String provider;
  final String animeId;
  final String animeTitle;
  final String image;
  final String episodeId;
  final int episodeNumber;
  final ScrollController scrollController;
  final List<DownloadGroup>? initialGroups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ref_ = (provider: provider, episodeId: episodeId);
    final hasInitial = initialGroups != null && initialGroups!.isNotEmpty;
    final groupsAsync = hasInitial
        ? AsyncValue<List<DownloadGroup>>.data(initialGroups!)
        : ref.watch(downloadGroupsProvider(ref_));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.download_rounded, color: AppColors.accentSoft),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      animeTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    Text(
                      'Episode $episodeNumber • unduhan per resolusi',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: groupsAsync.when(
            loading: () => ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: const [
                SkeletonBox(height: 56),
                SizedBox(height: 10),
                SkeletonBox(height: 56),
                SizedBox(height: 10),
                SkeletonBox(height: 56),
              ],
            ),
            error: (e, _) => ListView(
              controller: scrollController,
              children: [
                ErrorView(
                  message: e.toString(),
                  compact: true,
                  onRetry: () => ref.invalidate(downloadGroupsProvider(ref_)),
                ),
              ],
            ),
            data: (groups) {
              final sorted = [...groups]
                ..sort((a, b) => resolutionRank(b.resolution).compareTo(resolutionRank(a.resolution)));
              if (sorted.isEmpty || sorted.every((g) => g.links.isEmpty)) {
                return ListView(
                  controller: scrollController,
                  children: const [
                    EmptyView(
                      icon: Icons.file_download_off_rounded,
                      title: 'Tidak ada tautan unduhan',
                      subtitle: 'Provider ini tidak menyediakan unduhan untuk episode ini. '
                          'Coba provider lain (mis. Samehadaku / Gogoanime).',
                      compact: true,
                    ),
                  ],
                );
              }
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  for (final g in sorted) ...[
                    _GroupHeader(group: g),
                    const SizedBox(height: 8),
                    for (final link in g.links)
                      _LinkTile(
                        link: link,
                        onOpen: () async {
                          final ok = await openExternal(link.url);
                          if (!ok && context.mounted) {
                            await copyToClipboard(
                              context,
                              link.url,
                              label: link.isMagnet
                                  ? 'Tidak ada aplikasi torrent — magnet disalin'
                                  : 'Tidak bisa dibuka — tautan disalin',
                            );
                          }
                        },
                        onCopy: () => copyToClipboard(context, link.url),
                        saved: ref.watch(libraryProvider.select((l) => l.hasDownload(link.url))),
                        onSave: () async {
                          await ref.read(libraryProvider.notifier).addDownload(SavedDownload(
                                provider: provider,
                                animeId: animeId,
                                animeTitle: animeTitle,
                                image: image,
                                episodeId: episodeId,
                                episodeNumber: episodeNumber,
                                resolution: g.resolution,
                                server: link.server,
                                url: link.url,
                                format: g.format,
                                savedAt: DateTime.now(),
                              ));
                          if (context.mounted) {
                            showToast(context, 'Disimpan ke tab Unduhan', icon: Icons.bookmark_added_rounded);
                          }
                        },
                      ),
                    const SizedBox(height: 14),
                  ],
                  const Text(
                    'Tautan dibuka lewat browser / pengelola unduhan perangkat. '
                    'Magnet membutuhkan aplikasi torrent.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final DownloadGroup group;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MiniBadge(group.resolution.toUpperCase()),
        if (group.format != null) ...[
          const SizedBox(width: 6),
          MiniBadge(group.format!.toUpperCase(), color: AppColors.surfaceAlt),
        ],
        const SizedBox(width: 8),
        Text(
          '${group.links.length} server',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.link,
    required this.onOpen,
    required this.onCopy,
    required this.onSave,
    required this.saved,
  });

  final DownloadLink link;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            link.isMagnet ? Icons.link_rounded : Icons.cloud_download_outlined,
            size: 20,
            color: link.isMagnet ? AppColors.warning : AppColors.accentSoft,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  link.server,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
                Text(
                  hostOf(link.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Salin',
            onPressed: onCopy,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.muted),
          ),
          IconButton(
            tooltip: saved ? 'Sudah disimpan' : 'Simpan ke Unduhan',
            onPressed: saved ? null : onSave,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              saved ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
              size: 18,
              color: saved ? AppColors.success : AppColors.muted,
            ),
          ),
          const SizedBox(width: 2),
          PrimaryButton(label: 'Buka', icon: Icons.open_in_new_rounded, compact: true, onPressed: onOpen),
        ],
      ),
    );
  }
}
