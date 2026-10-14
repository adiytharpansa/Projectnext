# Deploy `workers/` ke Cloudflare

## 1. Login & secret

```bash
cd workers
npx wrangler login
npx wrangler secret put TORBOX_API_KEY   # opsional, untuk /api/v1/debrid/*
```

## 2. Deploy

```bash
npm run deploy
# → https://projectnext-api.<akun>.workers.dev
```

Variabel publik (`[vars]` di `wrangler.toml`) bisa dioverride per-environment
di dashboard Workers → Settings → Variables.

## 3. Arahkan frontend

Set di Cloudflare Pages (project `web/`):

```
NEXT_PUBLIC_API_URL=https://projectnext-api.<akun>.workers.dev
```

## Batasan yang sudah diverifikasi

- IP egress Workers sering diblokir anti-bot situs HTML (Gogo klasik,
  Samehadaku). Endpoint yang stabil di Workers: `torrentio`, `nyaa`,
  `crunchyroll`, `iqiyi`, `kitsu`, `gogoby`, TorBox, proxy m3u8.
- Rate-limit di Worker ini in-memory per-isolate (best-effort). Untuk proteksi
  ketat, aktifkan Rate Limiting Rules di dashboard Cloudflare.
- Cache in-memory per-isolate (TTL tetap jalan, hit-rate lebih rendah
  dibanding 1 proses Express). Untuk cache global, sambungkan KV/Upstash.
- Teknis: entry `src/shim.ts` WAJIB diimpor pertama — axios meng-capture
  konstruktor `Request` saat modul dimuat; workerd menolak field
  `cache`/`mode` sehingga perlu di-strip sebelum axios sempat evaluasi.
