import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/api/api_client.dart';
import '../../providers/app_providers.dart';
import '../../router.dart';

/// Profil & pengaturan: nama, statistik, server API, provider default,
/// preferensi pemutar, pembersihan data, tentang aplikasi.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final lib = ref.watch(libraryProvider);
    final online = ref.watch(serverOnlineProvider);
    final providers = ref.watch(providersProvider);
    final providerIds = ref.watch(providerIdsProvider);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        children: [
          const SizedBox(height: 12),
          SafeArea(
            bottom: false,
            child: _Header(
              name: settings.displayName,
              onEdit: () => _editName(context, ref, settings.displayName),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _Stat(label: 'Favorit', value: lib.watchlist.length, icon: Icons.bookmark_rounded),
              const SizedBox(width: 10),
              _Stat(label: 'Riwayat', value: lib.history.length, icon: Icons.history_rounded),
              const SizedBox(width: 10),
              _Stat(label: 'Unduhan', value: lib.downloads.length, icon: Icons.download_rounded),
            ],
          ),

          // ── server ──
          const _SectionLabel('Server API'),
          _Card(children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Alamat backend'),
              subtitle: Text(settings.apiBaseUrl, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              trailing: online.when(
                data: (ok) => _StatusDot(ok: ok),
                loading: () => const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => const _StatusDot(ok: false),
              ),
              onTap: () => _editServer(context, ref, settings.apiBaseUrl),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.public_rounded),
              title: const Text('Provider default'),
              subtitle: Text(
                providers.valueOrNull
                        ?.where((p) => p.id == settings.defaultProvider)
                        .map((p) => '${p.name} • ${p.languages.join('/')}')
                        .firstOrNull ??
                    settings.defaultProvider,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              onTap: () => _pickProvider(context, ref, providerIds, settings.defaultProvider),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Tes ulang koneksi & muat provider'),
              onTap: () {
                ref.invalidate(serverOnlineProvider);
                ref.invalidate(providersProvider);
                ref.invalidate(homeFeedProvider);
                showToast(context, 'Memuat ulang…');
              },
            ),
          ]),

          // ── pemutar ──
          const _SectionLabel('Pemutar'),
          _Card(children: [
            SwitchListTile(
              secondary: const Icon(Icons.skip_next_rounded),
              title: const Text('Putar episode berikutnya otomatis'),
              value: settings.autoplayNext,
              onChanged: (v) => ref.read(settingsProvider.notifier).setAutoplayNext(v),
            ),
            const Divider(height: 1, indent: 56),
            SwitchListTile(
              secondary: const Icon(Icons.shield_outlined),
              title: const Text('MP4 selalu lewat proxy'),
              subtitle: const Text(
                'Lebih kompatibel dengan server yang memblokir Referer; HLS selalu lewat proxy.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              value: settings.mp4ViaProxy,
              onChanged: (v) => ref.read(settingsProvider.notifier).setMp4ViaProxy(v),
            ),
          ]),

          // ── data ──
          const _SectionLabel('Data'),
          _Card(children: [
            ListTile(
              leading: const Icon(Icons.history_toggle_off_rounded),
              title: const Text('Hapus riwayat tonton'),
              enabled: lib.history.isNotEmpty,
              onTap: () async {
                await ref.read(libraryProvider.notifier).clearHistory();
                if (context.mounted) showToast(context, 'Riwayat dihapus');
              },
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.replay_rounded),
              title: const Text('Ulangi layar pengenalan'),
              onTap: () async {
                await ref.read(settingsProvider.notifier).setOnboardingDone(false);
                if (context.mounted) context.go(AppRoutes.onboarding);
              },
            ),
          ]),

          // ── tentang ──
          const _SectionLabel('Tentang'),
          _Card(children: [
            const ListTile(
              leading: AppLogo(size: 32),
              title: Text('${AppConfig.brandName} v${AppConfig.version}'),
              subtitle: Text(
                'Klien Flutter untuk Projectnext API',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.code_rounded),
              title: const Text('Kode sumber di GitHub'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.muted),
              onTap: () => launchUrl(Uri.parse(AppConfig.repoUrl), mode: LaunchMode.externalApplication),
            ),
          ]),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Gunakan dengan bijak. Konten berasal dari situs pihak ketiga.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────── dialog ─────────────

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Nama tampilan'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Nama kamu'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Simpan', style: TextStyle(color: AppColors.accentSoft)),
          ),
        ],
      ),
    );
    if (result != null) await ref.read(settingsProvider.notifier).setDisplayName(result);
  }

  Future<void> _editServer(BuildContext context, WidgetRef ref, String current) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _ServerDialog(initial: current),
    );
    if (result != null) {
      await ref.read(settingsProvider.notifier).setApiBaseUrl(result);
      ref.invalidate(providersProvider);
      ref.invalidate(homeFeedProvider);
      ref.invalidate(serverOnlineProvider);
    }
  }

  Future<void> _pickProvider(
    BuildContext context,
    WidgetRef ref,
    List<String> ids,
    String current,
  ) async {
    final providers = ref.read(providersProvider).valueOrNull;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Provider default',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            for (final id in ids)
              Builder(builder: (context) {
                ProviderMetaView? meta;
                if (providers != null) {
                  for (final p in providers) {
                    if (p.id == id) {
                      meta = ProviderMetaView(p.name, p.languages.join('/'), p.supports);
                    }
                  }
                }
                return ListTile(
                  dense: true,
                  leading: Icon(
                    id == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: id == current ? AppColors.accent : AppColors.muted,
                  ),
                  title: Text(meta?.name ?? id),
                  subtitle: meta == null
                      ? null
                      : Text(
                          '${meta.lang} • ${meta.supports.join(', ')}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 11),
                        ),
                  onTap: () => Navigator.of(ctx).pop(id),
                );
              }),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != current) {
      await ref.read(settingsProvider.notifier).setDefaultProvider(chosen);
      ref.invalidate(homeFeedProvider);
    }
  }
}

/// Ringkasan provider untuk daftar pilihan.
class ProviderMetaView {
  const ProviderMetaView(this.name, this.lang, this.supports);
  final String name;
  final String lang;
  final List<String> supports;
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog({required this.initial});

  final String initial;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);
  bool _testing = false;
  bool? _ok;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _ok = null;
    });
    final ok = await ApiClient(_ctrl.text).health();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _ok = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Alamat server API'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'http://192.168.1.10:3000'),
            onChanged: (_) => setState(() => _ok = null),
          ),
          const SizedBox(height: 10),
          const Text(
            'Emulator Android: http://10.0.2.2:3000 • Simulator iOS: http://localhost:3000 • '
            'HP fisik: IP LAN komputer, atau URL Render/Vercel/Cloudflare.',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
          ),
          if (_ok != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _StatusDot(ok: _ok!),
                const SizedBox(width: 6),
                Text(
                  _ok! ? 'Server merespons' : 'Server tidak merespons',
                  style: TextStyle(
                    fontSize: 12,
                    color: _ok! ? AppColors.success : AppColors.accentSoft,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _testing ? null : _test,
          child: Text(_testing ? 'Menguji…' : 'Tes'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Simpan', style: TextStyle(color: AppColors.accentSoft)),
        ),
      ],
    );
  }
}

// ───────────── potongan UI ─────────────

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.onEdit});

  final String name;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.gradient),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              const Text('Akun lokal • data tersimpan di perangkat',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Ubah nama',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.accentSoft, size: 20),
            const SizedBox(height: 6),
            Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.ok});

  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ok ? AppColors.success : AppColors.accentSoft,
        boxShadow: [
          BoxShadow(
            color: (ok ? AppColors.success : AppColors.accentSoft).withOpacity(0.5),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }
}
