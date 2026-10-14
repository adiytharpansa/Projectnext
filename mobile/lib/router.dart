import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/calendar/calendar_screen.dart';
import 'features/detail/detail_screen.dart';
import 'features/download/downloads_screen.dart';
import 'features/home/home_screen.dart';
import 'features/mylist/mylist_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/search/search_screen.dart';
import 'features/shell/main_shell.dart';
import 'features/watch/watch_screen.dart';
import 'providers/app_providers.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Pembangun lokasi — semua id dikirim lewat query agar slug yang mengandung
/// karakter khusus ("/", ":") tetap aman.
class AppRoutes {
  AppRoutes._();

  static const onboarding = '/onboarding';
  static const home = '/home';
  static const calendar = '/calendar';
  static const myList = '/mylist';
  static const downloads = '/downloads';
  static const profile = '/profile';
  static const search = '/search';
  static const detail = '/anime';
  static const watch = '/watch';

  static String searchWith({String? query, String? provider}) => Uri(
        path: search,
        queryParameters: {
          if (query != null && query.isNotEmpty) 'q': query,
          if (provider != null && provider.isNotEmpty) 'provider': provider,
        },
      ).toString();

  static String detailOf(String provider, String id) => Uri(
        path: detail,
        queryParameters: {'provider': provider, 'id': id},
      ).toString();

  static String watchOf({
    required String provider,
    required String episodeId,
    required String animeId,
    String? animeTitle,
    String? image,
    int? episodeNumber,
  }) =>
      Uri(
        path: watch,
        queryParameters: {
          'provider': provider,
          'episodeId': episodeId,
          'animeId': animeId,
          if (animeTitle != null) 'title': animeTitle,
          if (image != null) 'image': image,
          if (episodeNumber != null) 'ep': '$episodeNumber',
        },
      ).toString();
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final done = ref.read(settingsProvider).onboardingDone;
      final atOnboarding = state.matchedLocation == AppRoutes.onboarding;
      if (!done && !atOnboarding) return AppRoutes.onboarding;
      if (done && atOnboarding) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.calendar,
              builder: (context, state) => const CalendarScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.myList,
              builder: (context, state) => const MyListScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.downloads,
              builder: (context, state) => const DownloadsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.profile,
              builder: (context, state) => const ProfileScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: AppRoutes.search,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => SearchScreen(
          initialQuery: state.uri.queryParameters['q'],
          initialProvider: state.uri.queryParameters['provider'],
        ),
      ),
      GoRoute(
        path: AppRoutes.detail,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => DetailScreen(
          provider: state.uri.queryParameters['provider'] ?? '',
          id: state.uri.queryParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.watch,
        parentNavigatorKey: _rootKey,
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return WatchScreen(
            provider: q['provider'] ?? '',
            episodeId: q['episodeId'] ?? '',
            animeId: q['animeId'] ?? '',
            animeTitle: q['title'],
            image: q['image'],
            episodeNumber: int.tryParse(q['ep'] ?? ''),
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48),
              const SizedBox(height: 12),
              Text('Halaman tidak ditemukan: ${state.uri}'),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('Ke Beranda'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});
