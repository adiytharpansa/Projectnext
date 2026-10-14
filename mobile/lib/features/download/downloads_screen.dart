import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/net_image.dart';
import '../../providers/app_providers.dart';
import '../../router.dart';
import 'download_sheet.dart';

/// Tab Unduhan: tautan yang disimpan pengguna, dikelompokkan per anime.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(libraryProvider.select((l) => l.downloads));

    // Kelompokkan per anime, urutan sesuai waktu simpan terbaru.
    final groups = <String, List<SavedDownload>>{};
    for (final d in downloads) {
      groups.putIfAbsent('${d.provider}/${d.animeId}', () => []).add(d);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unduhan', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (downloads.isNotEmpty)
            IconButton(
              tooltip: 'Hapus semua',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final ok = await _confirm(context, 'Hapus semua tautan unduhan tersimpan?');
                if (ok) await ref.read(libraryProvider.notifier).clearDownloads();
              },
            ),
        ],
      ),
      body: downloads.isEmpty
          ? EmptyView(
              icon: Icons.download_outlined,
              title: 'Belum ada unduhan tersimpan',
              subtitle:
                  'Buka detail anime → tekan lama nomor episode atau tombol Unduh, lalu simpan tautan yang kamu mau.',
              actionLabel: 'Cari anime',
              onAction: () => context.push(AppRoutes.search),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
              children: [
                _Notice(),
                const SizedBox(height: 14),
                for (final entry in groups.entries) ...[
                  _AnimeGroup(items: entry.value),
                  const SizedBox(height: 16),
                ],
              ],
            ),
    );
  }

  static Future<bool> _confirm(BuildContext context, String message) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Konfirmasi'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus', style: TextStyle(color: AppColors.accentSoft)),
          ),
        ],
      ),
    );
    return res ?? false;
  }
}

class _Notice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.accentSoft, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tautan dibuka lewat browser / pengelola unduhan perangkat. '
              'File tersimpan di folder Unduhan sistem.',
              style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimeGroup extends ConsumerWidget {
  const _AnimeGroup({required this.items});

  final List<SavedDownload> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = items.first;
    final sorted = [...items]
      ..sort((a, b) {
        final byEp = a.episodeNumber.compareTo(b.episodeNumber);
        if (byEp != 0) return byEp;
        return resolutionRank(b.resolution).compareTo(resolutionRank(a.resolution));
      });

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => context.push(AppRoutes.detailOf(first.provider, first.animeId)),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  NetImage(
                    url: first.image,
                    provider: first.provider,
                    width: 48,
                    height: 64,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          first.animeTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${items.length} tautan • ${first.provider}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          for (final d in sorted)
            Dismissible(
              key: ValueKey(d.url),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: AppColors.accent.withOpacity(0.25),
                child: const Icon(Icons.delete_outline_rounded, color: AppColors.accentSoft),
              ),
              onDismissed: (_) => ref.read(libraryProvider.notifier).removeDownload(d.url),
              child: ListTile(
                dense: true,
                leading: Container(
                  width: 44,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'EP ${d.episodeNumber}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(
                  '${d.resolution.toUpperCase()}${d.format != null ? ' • ${d.format}' : ''} • ${d.server}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${hostOf(d.url)} • ${relativeDate(d.savedAt)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Salin',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.muted),
                      onPressed: () => copyToClipboard(context, d.url),
                    ),
                    PrimaryButton(
                      label: 'Buka',
                      icon: d.isMagnet ? Icons.link_rounded : Icons.open_in_new_rounded,
                      compact: true,
                      onPressed: () async {
                        final ok = await openExternal(d.url);
                        if (!ok && context.mounted) {
                          await copyToClipboard(context, d.url,
                              label: 'Tidak bisa dibuka — tautan disalin');
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
