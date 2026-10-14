# Projectnext

Modular anime scraper API ala **Consumet** — Node.js + TypeScript + Express. Provider OOP dengan `BaseProvider` abstrak:

| Provider | Jenis | search | info | watch | download |
|---|---|---|---|---|---|
| `gogo` | Stream EN | ✅ | ✅ | ✅ m3u8/MP4 | ✅ per resolusi |
| `gogoby` | Stream EN (klon WP, HLS+subtitle) | ✅ | ✅ | ✅ m3u8 | ⛔ tema tanpa unduhan |
| `samehadaku` | Stream ID | ✅ | ✅ | ✅ embed+server | ✅ MP4/MKV |
| `crunchyroll` | Metadata resmi | ✅ | ✅ poster HD | ⛔ DRM | ⛔ |
| `iqiyi` | Metadata iQIYI (film/donghua) | ✅ | ✅ via cache search | ⛔ DRM+signed | ⛔ |
| `torrentio` | Agregat torrent (via Kitsu) | ✅ | ✅ | ⛔ butuh debrid | ✅ magnet |
| `nyaa` | Torrent fansub | ✅ | ⛔ indeks saja | ⛔ butuh debrid | ✅ magnet+.torrent |

> <!-- omgithub:readme:start -->
> ## 🚀 Build, play, and remix with OMGithub
>
> **Remixed using [OMGithub.com](https://omgithub.com).**
>
> [![OMGithub](https://img.shields.io/badge/OMGithub-Open%20project-orange?style=for-the-badge)](https://omgithub.com/adiytharpansa/Projectnext)
> [![GitHub](https://img.shields.io/badge/GitHub-Source-181717?logo=github&style=for-the-badge)](https://github.com/adiytharpansa/Projectnext)
>
> - 🎮 [Open the project](https://omgithub.com/adiytharpansa/Projectnext).
> - ✨ [Remix this project](https://omgithub.com/?remix=adiytharpansa%2FProjectnext).
> - 💻 [Explore the source](https://github.com/adiytharpansa/Projectnext).
> - 🛠️ [Check build runs](https://github.com/adiytharpansa/Projectnext/actions).
> - 🐛 [Report an issue](https://github.com/adiytharpansa/Projectnext/issues).
> - 👤 [Explore the creator's projects](https://omgithub.com/adiytharpansa).
> - 🌍 [Create with OMGithub](https://omgithub.com).
> - 🧬 [Explore the remix source](https://github.com/adiytharpansa/Projectnext).
> <!-- omgithub:readme:end -->

## Fitur

- **Metadata + Poster HD** — search, sinopsis, genre, status, total episode, poster.
- **Stream Sources** — ekstrak `.m3u8`/MP4 + resolusi + subtitle (best-effort; bila embed terenkripsi, dikembalikan sebagai `type: "embed"` + `servers`).
- **Download Links** — dikelompokkan per resolusi (360p/480p/720p/1080p) + nama server.
- **Bypass proteksi** — endpoint proxy internal (`/api/proxy`, `/api/proxy/m3u8`) untuk CORS + Referer/User-Agent + rewrite playlist HLS.
- **OOP modular** — tambah provider baru tanpa ubah route/controller.

## Struktur

```
src/
  app.ts                  # factory Express (dipakai lokal + Vercel)
  index.ts                # entry lokal/Render (listen)
  config.ts               # env terpusat
  types.ts                # kontrak data antar provider
  providers/
    BaseProvider.ts       # class abstrak
    GogoanimeProvider.ts  # contoh provider global
    SamehadakuProvider.ts # contoh provider lokal ID
    index.ts              # registry (tambah provider di sini)
  services/httpClient.ts  # axios + UA rotation + Referer
  controllers/            # animeController, proxyController
  routes/                 # anime, proxy
  middlewares/            # ApiError, asyncHandler, errorMiddleware
  utils/                  # cache, url
api/index.ts              # handler serverless Vercel
```

## Menjalankan lokal

```bash
cp .env.example .env   # sesuaikan domain bila perlu
npm install
npm run dev            # http://localhost:3000
npm run build && npm start
```

## Endpoint

| Method | Endpoint | Deskripsi |
|---|---|---|
| GET | `/` | Info API + daftar endpoint |
| GET | `/api/health` | Healthcheck |
| GET | `/api/providers` | Daftar provider |
| GET | `/api/anime/:provider/search?query=naruto` | Pencarian |
| GET | `/api/anime/:provider/info/:id` | Detail + daftar episode |
| GET | `/api/anime/:provider/watch/:episodeId` | Stream sources + subtitle + servers |
| GET | `/api/anime/:provider/download/:episodeId` | Download per resolusi/server |
| GET | `/api/proxy?url=...&referer=...` | Proxy generik (img/ts/mp4/vtt) |
| GET | `/api/proxy/m3u8?url=...&referer=...` | Proxy HLS + rewrite segmen |

### API v1 (untuk klien my-anime)

| Method | Endpoint | Deskripsi |
|---|---|---|
| GET | `/api/v1/anime/search?query=naruto&provider=` | Pencarian; `provider` kosong = agregat semua provider |
| GET | `/api/v1/anime/info?provider=gogo&id=naruto` | Detail + episode (default provider `gogo`) |
| GET | `/api/v1/anime/watch?provider=gogo&episodeId=naruto-episode-10` | Stream + subtitle + download |
| GET | `/api/v1/anime/download?provider=gogo&episodeId=...` | Download per resolusi/server |
| GET | `/api/v1/debrid/status` | Status debrid gratis (butuh `TORBOX_API_KEY`?) |
| POST | `/api/v1/debrid/unrestrict` `{ magnet }` | Magnet → link HTTP (cached = instan) |
| GET | `/api/v1/debrid/torrent/:id` | Poll progres unduhan |

Contoh:

```bash
curl "http://localhost:3000/api/anime/gogo/search?query=naruto"
curl "http://localhost:3000/api/anime/gogo/info/naruto"
curl "http://localhost:3000/api/anime/gogo/watch/naruto-episode-10"
curl "http://localhost:3000/api/anime/samehadaku/search?query=one%20piece"
curl "http://localhost:3000/api/anime/samehadaku/info/one-piece"
# Putar HLS tanpa CORS:
# http://localhost:3000/api/proxy/m3u8?url=<encoded-m3u8>&referer=<encoded-embed-origin>
```

Semua respons sukses berbentuk `{ success: true, status: 200, data: ... }`, error `{ success: false, status, message }`.

## Aplikasi mobile Anilab (`mobile/`)

Klien **Flutter** (Android/iOS) bergaya dark + aksen merah: onboarding, beranda (hero, Top Hits, lanjutkan menonton), cari, detail + grid episode, pemutar lanskap (HLS via proxy, subtitle, auto-next), unduhan per resolusi, jadwal rilis, Daftarku, profil/pengaturan server. Lihat `mobile/README.md`.

```bash
cd mobile && ./setup.sh && flutter run   # backend: http://10.0.2.2:3000 (emulator Android)
```

CI Flutter: `.github/workflows/mobile.yml` (analyze, test, build web + APK; artifact & ref `refs/preview/*`).
Preview web dengan data contoh: `node scripts/mock-api.mjs --port 8080 --static <hasil flutter build web>`.

## Frontend my-anime (`web/`)

Klien Next.js (App Router) + Tailwind dark theme + HLS.js + Supabase. Lihat `web/README.md`.

```bash
cd web && cp .env.example .env.local && npm install && npm run dev  # :3001
```

Halaman: `/` (hero + Lanjutkan menonton + Favorit), `/search`, `/anime/[provider]/[id]`, `/watch/[provider]/[episodeId]` (player HLS via proxy + unduhan per resolusi/server + prev/next + auto-save riwayat).

## Tambah provider baru

1. Buat `src/providers/OtakudesuProvider.ts` extends `BaseProvider`, implementasikan `search`, `fetchInfo`, `fetchSources`, `fetchDownloadLinks` (lihat `GogoanimeProvider.ts` sebagai template).
2. Daftarkan di `src/providers/index.ts`: `providers.set('otakudesu', new OtakudesuProvider())`.
3. Langsung tersedia di `/api/anime/otakudesu/...` — tanpa ubah route/controller.

## Deploy

- **Vercel** — `vercel.json` sudah mengarah ke `api/index.ts` (serverless). Set env `GOGO_BASE_URL`, `GOGO_AJAX_URL`, `SAMEHADAKU_BASE_URL` di dashboard.
- **Render** — `render.yaml` (build `npm install && npm run build`, start `npm start`). Atau manual: New Web Service → repo ini → build/start sama.
- **Cloudflare Workers** — folder `workers/` (Hono, reuse semua provider). Lihat `workers/DEPLOY.md`. Terverifikasi via `wrangler dev`: scrape torrentio/nyaa + rantai HLS gogoby + rewrite proxy m3u8 jalan. Batasan: IP egress Workers sering diblokir anti-bot situs HTML — endpoint paling stabil: torrentio/nyaa/crunchyroll/iqiyi/debrid/proxy.
- **Cloudflare Pages** — folder `web/` via `npm run pages:build` (butuh flag `nodejs_compat`). Terverifikasi lokal: `/`, `/search`, `/anime`, `/watch` 200 di workerd.
- **Cloudflare Tunnel** — `tunnel/config.yml` (named, butuh domain) atau `tunnel/quick.sh [PORT]` (URL publik instan tanpa login). Terverifikasi: URL trycloudflare → 200.

## Env

| Var | Default | Keterangan |
|---|---|---|
| `PORT` | 3000 | Port lokal (Render/Vercel mengatur sendiri) |
| `GOGO_BASE_URLS` | `https://gogoanime3.net` | Daftar mirror Gogo dipisah koma, dicoba berurutan |
| `GOGO_AJAX_URL` | `https://ajax.gogo-load.com` | Endpoint ajax episode list |
| `SAMEHADAKU_BASE_URLS` | `https://v2.samehadaku.how,...` | Daftar mirror Samehadaku dipisah koma |
| `TORBOX_API_KEY` | *(kosong)* | Debrid GRATIS torbox.app → magnet jadi link stream (maks 10GB, 1/24 jam, 10/bln; cached bebas slot) |
| `CRUNCHYROLL_BASIC_TOKEN` | *(token publik bawaan)* | Override bila token bawaan dicabut |
| `CACHE_TTL_SECONDS` | 300 | TTL cache in-memory |
| `RATE_LIMIT_MAX` | 120 | Maks request/menit per IP |
| `CORS_ORIGIN` | `*` | Origin diizinkan |

## Catatan operasional (penting)

- **Domain sumber berganti-ubah.** `samehadaku.email` (2024) kini dibajak, `anitaku.pe` jadi domain parkir, dan sebagian mirror Gogo memasang JS-challenge. Bila endpoint mengembalikan `502 Semua mirror gagal`, cari domain aktif terbaru lalu set `GOGO_BASE_URLS` / `SAMEHADAKU_BASE_URLS` (bisa beberapa, dipisah koma) — tanpa perlu ubah kode atau redeploy logic.
- **Cloudflare.** Mirror yang menampilkan "Just a moment..." tidak bisa di-scrape axios biasa dari server; pilih mirror lain atau akses dari network yang lolos.
- **Struktur HTML berubah.** Bila mirror valid tapi hasil kosong, sesuaikan selector di `GogoanimeProvider.ts` / `SamehadakuProvider.ts` (tiap selector terdokumentasi di komentar).
- **Embed terenkripsi.** Server yang anti-hotlink dikembalikan sebagai `type: "embed"` beserta `servers` agar frontend tetap bisa me-load via iframe/proxy.
- Gunakan secara bijak dan patuhi ToS situs sumber.
