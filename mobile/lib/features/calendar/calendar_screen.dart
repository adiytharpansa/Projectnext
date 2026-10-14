import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/net_image.dart';
import '../../providers/app_providers.dart';
import '../../router.dart';

/// Rilis: jadwal mingguan yang dibangun dari judul di Daftarku —
/// episode terbaru tiap judul dikelompokkan menurut hari rilisnya.
/// (Backend belum menyediakan endpoint jadwal global.)
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  /// 0 = Senin … 6 = Minggu; -1 = semua.
  late int _day = DateTime.now().weekday - 1;

  @override
  Widget build(BuildContext context) {
    final watchlist = ref.watch(libraryProvider.select((l) => l.watchlist));
    final latest = ref.watch(latestEpisodesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rilis Episode', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Segarkan',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(latestEpisodesProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          _WeekStrip(selected: _day, onSelect: (d) => setState(() => _day = d)),
          const SizedBox(height: 6),
          Expanded(
            child: watchlist.isEmpty
                ? EmptyView(
                    icon: Icons.calendar_month_outlined,
                    title: 'Jadwal masih kosong',
                    subtitle:
                        'Tambahkan anime ke Daftarku — episode terbarunya akan muncul di sini menurut hari rilis.',
                    actionLabel: 'Cari anime',
                    onAction: () => context.push(AppRoutes.search),
                  )
                : latest.when(
                    loading: () => ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                      itemCount: 4,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, __) => const SkeletonBox(height: 84, radius: 14),
                    ),
                    error: (e, _) => ErrorView(
                      message: e.toString(),
                      onRetry: () => ref.invalidate(latestEpisodesProvider),
                    ),
                    data: (items) => _buildList(context, items),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, List<LatestEpisode> items) {
    // Kelompokkan: hari (0..6) atau -2 untuk tanpa tanggal.
    int dayOf(LatestEpisode it) {
      final d = parseLooseDate(it.episode.date);
      return d == null ? -2 : d.weekday - 1;
    }

    final filtered = _day == -1
        ? items
        : items.where((it) {
            final d = dayOf(it);
            return d == _day || d == -2;
          }).toList();

    final dated = filtered.where((it) => dayOf(it) >= 0).toList()
      ..sort((a, b) {
        final da = parseLooseDate(a.episode.date)!;
        final db = parseLooseDate(b.episode.date)!;
        return db.compareTo(da);
      });
    final undated = filtered.where((it) => dayOf(it) < 0).toList();

    if (filtered.isEmpty) {
      return const EmptyView(
        icon: Icons.event_busy_rounded,
        title: 'Tidak ada rilis di hari ini',
        subtitle: 'Pilih hari lain atau "Semua".',
        compact: true,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        if (dated.isNotEmpty) ...[
          _GroupTitle(
            _day == -1 ? 'Dengan tanggal rilis' : weekdayNamesId[_day],
            count: dated.length,
          ),
          for (final it in dated) _ReleaseTile(item: it),
        ],
        if (undated.isNotEmpty) ...[
          _GroupTitle('Episode terbaru (tanpa tanggal)', count: undated.length),
          for (final it in undated) _ReleaseTile(item: it),
        ],
        const SizedBox(height: 8),
        const Text(
          'Jadwal disusun dari judul di Daftarku. Provider yang tidak mencantumkan tanggal '
          '(mis. Gogoanime) tampil di bagian "tanpa tanggal".',
          style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
        ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday - 1;
    return SizedBox(
      height: 72,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _DayPill(
            label: 'Semua',
            sub: '',
            selected: selected == -1,
            onTap: () => onSelect(-1),
          ),
          for (var d = 0; d < 7; d++) ...[
            const SizedBox(width: 8),
            _DayPill(
              label: weekdayShortId[d],
              sub: d == today ? 'hari ini' : '',
              selected: selected == d,
              onTap: () => onSelect(d),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 64,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected ? Colors.white : Colors.white70,
              ),
            ),
            if (sub.isNotEmpty)
              Text(
                sub,
                style: TextStyle(
                  fontSize: 9.5,
                  color: selected ? Colors.white70 : AppColors.accentSoft,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title, {required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(width: 8),
          MiniBadge('$count', color: AppColors.surfaceAlt),
        ],
      ),
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({required this.item});

  final LatestEpisode item;

  @override
  Widget build(BuildContext context) {
    final a = item.anime;
    final ep = item.episode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(AppRoutes.watchOf(
          provider: a.provider,
          episodeId: ep.id,
          animeId: a.id,
          animeTitle: a.title,
          image: a.image,
          episodeNumber: ep.number,
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
                url: a.image,
                provider: a.provider,
                width: 52,
                height: 70,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        MiniBadge('EP ${ep.number}'),
                        const SizedBox(width: 6),
                        if (item.info.status != null)
                          Flexible(
                            child: Text(
                              item.info.status!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ep.date ?? (ep.title ?? '${item.info.totalEpisodes} episode total'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Detail',
                onPressed: () => context.push(AppRoutes.detailOf(a.provider, a.id)),
                icon: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
