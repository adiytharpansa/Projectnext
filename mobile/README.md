# Anilab — aplikasi Flutter untuk Projectnext

Klien mobile (Android & iOS) bergaya *dark + aksen merah* yang memakai backend
**Projectnext API** (`../src`, Express) lewat endpoint `/api/v1/*` dan `/api/proxy`.

| Layar | Isi |
|---|---|
| **Onboarding** | Sambutan + pengaturan alamat server API (tes koneksi) |
| **Beranda** | Hero banner (auto-geser), *Lanjutkan Menonton*, *Top Hits* berperingkat, *Episode Baru* dari Daftarku, Favorit, chip provider |
| **Cari** | Debounce 500 ms, filter provider (agregat semua / satu), saran populer, hasil dengan tombol Putar & simpan |
| **Detail** | Gambar besar + tombol putar, chip info (eps/tahun/genre/status/skor), sinopsis *Selengkapnya*, grid episode (rentang 50-an, penanda sudah/sedang ditonton, tekan lama = unduhan), batch, rekomendasi |
| **Pemutar** | Lanskap penuh, HLS lewat `/api/proxy/m3u8`, MP4 langsung → fallback proxy, subtitle VTT/SRT, kecepatan, pilih kualitas/server, kunci layar, ±10 dtk (double-tap), prev/next, daftar episode, resume & auto-next |
| **Unduhan** | Lembar tautan per resolusi (360p–1080p) & server; buka via browser/pengelola unduhan, salin, simpan; magnet → aplikasi torrent |
| **Rilis** | Jadwal mingguan dari judul di Daftarku (tanggal episode diparse dari provider) |
| **Daftarku** | Favorit (grid) & Riwayat (progres, geser untuk hapus) |
| **Profil** | Nama, statistik, server API (+tes), provider default, auto-next, MP4 via proxy, hapus riwayat, tentang |

Semua data pengguna (favorit, riwayat, unduhan tersimpan, pengaturan) disimpan
lokal di perangkat (`shared_preferences`) — tidak perlu akun.

## Menjalankan

Prasyarat: Flutter **3.19+** (Dart ≥ 3.3) dan backend Projectnext yang hidup
(`npm run dev` di root repo → `http://localhost:3000`).

```bash
cd mobile
./setup.sh          # flutter create (android/ios) + patch izin internet/cleartext + pub get
flutter run         # pilih emulator/perangkat
```

> Folder `android/` dan `ios/` sengaja tidak di-commit; `setup.sh` membuatnya
> dari template Flutter versi kamu, lalu menambahkan `INTERNET`,
> `usesCleartextTraffic` (agar `http://` lokal jalan) dan ATS di iOS.

Alamat backend:

| Target | URL |
|---|---|
| Emulator Android | `http://10.0.2.2:3000` (default otomatis) |
| Simulator iOS / desktop | `http://localhost:3000` |
| HP fisik | `http://<IP-LAN-komputer>:3000`, atau URL deploy (Render / Vercel / Cloudflare Workers) |

Ubah kapan saja di **Profil → Server API** (ada tombol *Tes*).

## Struktur kode

```
lib/
  main.dart                 # bootstrap: SharedPreferences, orientasi, ProviderScope
  app.dart                  # MaterialApp.router + tema
  router.dart               # go_router: shell 5 tab + rute penuh (search, detail, watch)
  core/
    config/app_config.dart  # nama merek, seed "Top Hits", default URL
    theme/app_theme.dart    # palet & ThemeData
    utils/formatters.dart   # durasi, tahun, tanggal longgar, resolusi
    widgets/                # NetImage (fallback proxy), PosterCard, tombol, skeleton, state kosong/error
  data/
    models/models.dart      # cerminan src/types.ts (parser toleran)
    api/api_client.dart     # Dio → /api/v1/*, /api/proxy, envelope {success,status,data}
    local/settings_store.dart, library_store.dart   # pengaturan, favorit, riwayat, unduhan
  providers/app_providers.dart  # Riverpod: api, settings, library, search/info/watch/download, homeFeed, latestEpisodes
  features/
    onboarding/ shell/ home/ search/ detail/ watch/ download/ calendar/ mylist/ profile/
test/                        # unit model+formatter, widget dasar
```

Pemetaan endpoint:

| Fitur | Endpoint backend |
|---|---|
| Provider | `GET /api/v1/providers` |
| Cari | `GET /api/v1/anime/search?query=&provider=` |
| Detail + episode | `GET /api/v1/anime/info?provider=&id=` |
| Sumber video | `GET /api/v1/anime/watch?provider=&episodeId=` |
| Unduhan | `GET /api/v1/anime/download?provider=&episodeId=` |
| Stream HLS / subtitle / gambar | `GET /api/proxy/m3u8?url=&referer=` · `GET /api/proxy?url=&referer=` |
| Cek server | `GET /api/health` |

## Catatan desain & keterbatasan

- **Beranda tanpa endpoint trending** — backend belum punya "trending/terbaru", jadi
  *Top Hits* dibangun dari pencarian judul populer (`AppConfig.topHitSeeds`, maks.
  3 permintaan paralel agar situs sumber tidak membatasi). *Episode Baru* & *Rilis*
  diturunkan dari judul di Daftarku.
- **Sumber embed** — bila provider hanya mengembalikan pemutar embed (tidak ada
  `.m3u8`/MP4 langsung), aplikasi menawarkan *Buka di browser* dan tautan unduhan.
  Pemutar in-app WebView bisa ditambahkan nanti (`webview_flutter`).
- **Unduhan** memakai browser / pengelola unduhan sistem (tanpa izin penyimpanan
  khusus). Unduhan in-app bisa ditambahkan dengan `flutter_downloader`/`dio` + `path_provider`.
- **Debrid (TorBox)** belum dipakai di mobile; magnet dibuka ke aplikasi torrent.
- Mengganti nama merek: ubah `AppConfig.brandName` (dan label di `setup.sh`).

## Perintah berguna

```bash
flutter analyze
flutter test
flutter build apk --release
flutter build ipa            # butuh macOS + sertifikat
```
