import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/net_image.dart';
import '../../core/widgets/poster_card.dart';
import '../../data/models/models.dart';
import '../../providers/app_providers.dart';
import '../../router.dart';

/// Layar Cari: kolom pencarian + filter provider; saat kosong menampilkan
/// "Pencarian populer" (grid poster dari beranda + chip saran), saat ada
/// kueri menampilkan hasil dari backend (agregat semua provider atau satu).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery, this.initialProvider});

  final String? initialQuery;
  final String? initialProvider;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  String? _provider;

  @override
  void initState() {
    super.initState();
    _provider = widget.initialProvider;
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _ctrl.text = widget.initialQuery!;
      _query = widget.initialQuery!.trim();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
    });
  }

  void _submit(String v) {
    _debounce?.cancel();
    setState(() => _query = v.trim());
  }

  void _useSuggestion(String s) {
    _ctrl.text = s;
    _ctrl.selection = TextSelection.collapsed(offset: s.length);
    _submit(s);
  }

  @override
  Widget build(BuildContext context) {
    final providerIds = ref.watch(providerIdsProvider);
    final providers = ref.watch(providersProvider).valueOrNull;

    String nameOf(String id) {
      if (providers != null) {
        for (final p in providers) {
          if (p.id == id) return p.name;
        }
      }
      return id;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Cari', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: 'Cari anime…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.cancel_rounded, size: 20),
                        onPressed: () {
                          _ctrl.clear();
                          _submit('');
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _FilterChip(
                  label: 'Semua',
                  selected: _provider == null,
                  onTap: () => setState(() => _provider = null),
                ),
                for (final id in providerIds) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: nameOf(id),
                    selected: _provider == id,
                    onTap: () => setState(() => _provider = id),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _query.length < 2
                ? _PopularSection(onPick: _useSuggestion)
                : _ResultsSection(query: _query, provider: _provider),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

// ───────────── populer ─────────────

class _PopularSection extends ConsumerWidget {
  const _PopularSection({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider).valueOrNull;
    final history = ref.watch(libraryProvider.select((l) => l.history));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const Text('Pencarian populer',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in AppConfig.popularSearches)
              ActionChip(
                label: Text(s),
                avatar: const Icon(Icons.trending_up_rounded, size: 15, color: AppColors.accentSoft),
                onPressed: () => onPick(s),
              ),
          ],
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text('Terakhir ditonton',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in history.take(6))
                ActionChip(
                  label: Text(truncate(h.animeTitle, 24)),
                  avatar: const Icon(Icons.history_rounded, size: 15, color: AppColors.muted),
                  onPressed: () => onPick(h.animeTitle),
                ),
            ],
          ),
        ],
        if (feed != null && feed.topHits.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text('Sedang populer',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.68,
            ),
            itemCount: feed.topHits.length,
            itemBuilder: (context, i) {
              final a = feed.topHits[i];
              return LayoutBuilder(
                builder: (context, c) => PosterCard(
                  anime: a,
                  width: c.maxWidth,
                  height: c.maxHeight,
                  onTap: () => context.push(AppRoutes.detailOf(a.provider, a.id)),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

// ───────────── hasil ─────────────

class _ResultsSection extends ConsumerWidget {
  const _ResultsSection({required this.query, required this.provider});

  final String query;
  final String? provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (query: query, provider: provider);
    final result = ref.watch(searchProvider(args));

    return result.when(
      loading: () => ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => const Row(
          children: [
            SkeletonBox(width: 96, height: 136, radius: 12),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 180, height: 18),
                  SizedBox(height: 10),
                  SkeletonBox(width: 120, height: 12),
                  SizedBox(height: 10),
                  SkeletonBox(width: 220, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
      error: (e, _) => ErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(searchProvider(args)),
        onSettings: () => context.go(AppRoutes.profile),
      ),
      data: (res) {
        if (res.results.isEmpty) {
          return EmptyView(
            icon: Icons.search_off_rounded,
            title: 'Tidak ada hasil untuk "$query"',
            subtitle: res.errors.isNotEmpty
                ? 'Beberapa provider gagal: ${res.errors.map((e) => e.provider).join(', ')}'
                : 'Coba kata kunci lain atau ganti provider.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: res.results.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Text(
                      '${res.count} hasil',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                    const Spacer(),
                    if (res.errors.isNotEmpty)
                      Tooltip(
                        message: res.errors.map((e) => '${e.provider}: ${e.message}').join('\n'),
                        triggerMode: TooltipTriggerMode.tap,
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 14, color: AppColors.warning),
                            const SizedBox(width: 4),
                            Text(
                              '${res.errors.length} provider gagal',
                              style: const TextStyle(color: AppColors.warning, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            }
            return _ResultTile(anime: res.results[i - 1]);
          },
        );
      },
    );
  }
}

class _ResultTile extends ConsumerWidget {
  const _ResultTile({required this.anime});

  final AnimeSummary anime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(libraryProvider.select((l) => l.isFavorite(anime.key)));
    final year = yearOf(anime.releaseDate);
    final score = cleanScore(anime.score);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: () => context.push(AppRoutes.detailOf(anime.provider, anime.id)),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NetImage(
                url: anime.image,
                provider: anime.provider,
                width: 92,
                height: 130,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        InfoChip(anime.provider.toUpperCase(), highlight: true),
                        if (anime.type != null) InfoChip(anime.type!),
                        if (year != null) InfoChip(year),
                        if (score != null) InfoChip(score, icon: Icons.star_rounded),
                      ],
                    ),
                    if (anime.genres.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        anime.genres.take(4).join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            label: 'Putar',
                            icon: Icons.play_arrow_rounded,
                            expanded: true,
                            onPressed: () => context.push(AppRoutes.detailOf(anime.provider, anime.id)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlassIconButton(
                          icon: isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                          color: isFav ? AppColors.accentSoft : Colors.white,
                          onPressed: () => ref.read(libraryProvider.notifier).toggleFavorite(anime),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
