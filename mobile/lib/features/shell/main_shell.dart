import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// Kerangka utama dengan navigasi bawah 5 tab (Beranda, Rilis, Daftarku,
/// Unduhan, Profil) — tiap tab punya tumpukan navigasi sendiri.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = <_NavItem>[
    _NavItem('Beranda', Icons.home_outlined, Icons.home_rounded),
    _NavItem('Rilis', Icons.calendar_month_outlined, Icons.calendar_month_rounded),
    _NavItem('Daftarku', Icons.bookmark_border_rounded, Icons.bookmark_rounded),
    _NavItem('Unduhan', Icons.download_outlined, Icons.download_rounded),
    _NavItem('Profil', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      // Tap tab yang sedang aktif → kembali ke akar tumpukan tab tsb.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = navigationShell.currentIndex;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.96),
          border: const Border(top: BorderSide(color: AppColors.border, width: 0.6)),
        ),
        padding: EdgeInsets.only(bottom: bottomInset, top: 8),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: _items[i],
                    active: i == current,
                    onTap: () => _onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: active ? 1.1 : 1,
            duration: const Duration(milliseconds: 180),
            child: Icon(active ? item.activeIcon : item.icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
