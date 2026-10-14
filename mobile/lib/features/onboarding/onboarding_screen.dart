import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/api/api_client.dart';
import '../../providers/app_providers.dart';
import '../../router.dart';

/// Dua halaman: sambutan (kolase miring ala mockup) → atur alamat server API.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    _page.animateToPage(
      i,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    await ref.read(settingsProvider.notifier).setOnboardingDone(true);
    if (mounted) context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _PosterCollage(),
          // Gradasi dari atas transparan ke latar gelap di bawah
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.45, 0.7],
                colors: [Colors.transparent, Color(0xAA0D0D12), AppColors.bg],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                Expanded(
                  flex: 6,
                  child: PageView(
                    controller: _page,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: [
                      _WelcomePage(onNext: () => _goTo(1), onSkip: _finish),
                      _ServerPage(onDone: _finish, onBack: () => _goTo(0)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 14,
            child: _Dots(count: 2, index: _index),
          ),
        ],
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext, required this.onSkip});

  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const AppLogo(size: 44),
          const SizedBox(height: 22),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 36,
                    height: 1.1,
                  ),
              children: const [
                TextSpan(text: 'Welcome To\n'),
                TextSpan(
                  text: AppConfig.brandName,
                  style: TextStyle(color: AppColors.accent),
                ),
                TextSpan(text: '.'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            AppConfig.tagline,
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    onTap: onSkip,
                    borderRadius: BorderRadius.circular(999),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text(
                          'Masuk sebagai Tamu',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  label: 'Mulai',
                  icon: Icons.arrow_forward_rounded,
                  expanded: true,
                  onPressed: onNext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServerPage extends ConsumerStatefulWidget {
  const _ServerPage({required this.onDone, required this.onBack});

  final VoidCallback onDone;
  final VoidCallback onBack;

  @override
  ConsumerState<_ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends ConsumerState<_ServerPage> {
  final _ctrl = TextEditingController();
  bool _testing = false;
  bool? _online;

  @override
  void initState() {
    super.initState();
    _ctrl.text = ref.read(settingsProvider).apiBaseUrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _online = null;
    });
    final ok = await ApiClient(_ctrl.text).health();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _online = ok;
    });
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).setApiBaseUrl(_ctrl.text);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text(
            'Hubungkan ke\nserver Projectnext',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  height: 1.15,
                ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Masukkan alamat backend API (Express) yang sudah berjalan. '
            'Emulator Android memakai 10.0.2.2, perangkat fisik memakai IP LAN komputer.',
            style: TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'http://192.168.1.10:3000',
              prefixIcon: const Icon(Icons.dns_outlined),
              suffixIcon: _online == null
                  ? null
                  : Icon(
                      _online! ? Icons.check_circle_rounded : Icons.error_rounded,
                      color: _online! ? AppColors.success : AppColors.accentSoft,
                    ),
            ),
            onChanged: (_) => setState(() => _online = null),
          ),
          const SizedBox(height: 10),
          if (_online == false)
            const Text(
              'Server tidak merespons. Kamu tetap bisa lanjut dan mengubahnya nanti di Profil.',
              style: TextStyle(color: AppColors.accentSoft, fontSize: 12),
            ),
          if (_online == true)
            const Text(
              'Terhubung! Server API siap dipakai.',
              style: TextStyle(color: AppColors.success, fontSize: 12),
            ),
          const SizedBox(height: 22),
          Row(
            children: [
              OutlineButtonPill(
                label: 'Tes koneksi',
                icon: Icons.wifi_tethering_rounded,
                onPressed: _testing ? null : _test,
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Simpan & Lanjut',
                icon: Icons.check_rounded,
                loading: _testing,
                onPressed: _save,
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.muted),
            label: const Text('Kembali', style: TextStyle(color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index ? AppColors.accent : AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

/// Kolase pita miring (tanpa aset gambar) yang meniru latar mockup —
/// tiga pita bergradasi dengan tipografi judul besar.
class _PosterCollage extends StatelessWidget {
  const _PosterCollage();

  static const _bands = <_Band>[
    _Band('NARUTO', [Color(0xFFFF7A18), Color(0xFF2B1B0E)]),
    _Band('BLEACH', [Color(0xFF8E0E1C), Color(0xFF14080A)]),
    _Band('JUJUTSU KAISEN', [Color(0xFF1F2A6B), Color(0xFF0B0E1F)]),
    _Band('DEMON SLAYER', [Color(0xFF0E5E4C), Color(0xFF07120F)]),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bandHeight = size.height * 0.2;

    return ClipRect(
      child: OverflowBox(
        maxWidth: size.width * 1.6,
        maxHeight: size.height * 1.4,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewY(-0.22),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _bands.length; i++)
                Container(
                  height: bandHeight,
                  width: size.width * 1.6,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _bands[i].colors,
                      begin: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
                      end: i.isEven ? Alignment.centerRight : Alignment.centerLeft,
                    ),
                  ),
                  alignment: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.35),
                  child: Text(
                    _bands[i].title,
                    style: TextStyle(
                      fontSize: bandHeight * 0.42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: Colors.white.withOpacity(0.9),
                      shadows: const [Shadow(color: Colors.black54, blurRadius: 16)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Band {
  const _Band(this.title, this.colors);
  final String title;
  final List<Color> colors;
}
