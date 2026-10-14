# my-anime (web/)

Klien Next.js (App Router) + Tailwind dark theme untuk backend **Projectnext** + **Supabase**.

## Jalankan

```bash
cd web
cp .env.example .env.local   # isi NEXT_PUBLIC_API_URL (+ Supabase bila ada)
npm install
npm run dev                  # http://localhost:3001
```

Backend Projectnext harus jalan dulu (`npm run dev` di root repo, default `:3000`).

## Halaman

| Rute | Fungsi |
|---|---|
| `/` | Hero + pencarian, Lanjutkan menonton, Favorit |
| `/search?q=&provider=` | Grid poster responsif + filter provider |
| `/anime/[provider]/[id]` | Poster HD, sinopsis, genre/status, episode grid/list, tombol favorit |
| `/watch/[provider]/[episodeId]` | VideoPlayer HLS + DownloadSection per resolusi/server + prev/next + **panel streaming torrent gratis (TorBox)** |

## Keputusan teknis penting

- **Anti-gagal CORS/Referer:** semua URL `.m3u8` diputar lewat `GET {API}/api/proxy/m3u8?url=&referer=` (playlist di-rewrite ke proxy), MP4 langsung, embed tak ter-resolve via `<iframe>`. Lihat `lib/api.ts → proxiedStreamUrl`.
- **Kualitas:** HLS.js dengan selector Auto + level manual; ganti server tanpa reload halaman.
- **Supabase opsional:** tanpa env → otomatis mode localStorage (`lib/watchlist.ts`), UI identik. Dengan env → tabel `watchlist` & `history` (lihat `supabase/schema.sql`), `user_id` = ID perangkat anonim.
- **Sumber torrent:** tab pencarian mencakup Crunchyroll (metadata), Torrentio & Nyaa (magnet). Di watch page, magnet otomatis ditawarkan ke `DebridPanel`: cek status backend → unrestrict → poll → putar. Tanpa `TORBOX_API_KEY` di backend, panel sembunyi rapi.
- **Gambar remote:** `next.config.mjs` mengizinkan semua host https (poster dari banyak CDN sumber).

## Deploy (Vercel)

Import folder `web/` sebagai project, set env `NEXT_PUBLIC_API_URL` ke URL backend production + kredensial Supabase. `npm run build` harus hijau.

## Deploy (Cloudflare Pages) — terverifikasi lokal

Butuh Next 15 (paket `next@15.5.2` di-pin karena batas peer adapter).

```bash
cd web
npm run pages:build     # output ke .vercel/output (bukti lokal: wrangler pages dev → semua rute 200)
```

Lalu di dashboard Pages: Create project → hubungkan repo → **Framework: Next.js** →
Build command `npx @cloudflare/next-on-pages` (atau `npm run pages:build`) →
env `NEXT_PUBLIC_API_URL` (+ Supabase bila ada) →
**Compatibility flag: `nodejs_compat`** (wajib — worker butuh `node:buffer`).

Catatan: rute dinamis memakai `export const runtime = 'edge'` agar lolos build adapter.
