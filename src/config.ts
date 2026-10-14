/** Parse env daftar URL dipisah koma, mis. "https://a.net,https://b.net". */
function urlList(pluralKey: string, singleKey: string, def: string): string[] {
  const raw = process.env[pluralKey] ?? process.env[singleKey] ?? def;
  return raw
    .split(',')
    .map((s) => s.trim().replace(/\/$/, ''))
    .filter(Boolean);
}

/** Centralized config via env. */
export const appConfig = {
  port: Number(process.env.PORT ?? 3000),
  nodeEnv: process.env.NODE_ENV ?? 'development',
  /**
   * Daftar mirror dicoba berurutan (fallback) karena domain
   * Gogo/Samehadaku sering ganti / kena anti-bot per region.
   * Contoh: GOGO_BASE_URLS="https://gogoanime3.net,https://gogoanime.by"
   */
  gogoBaseUrls: urlList(
    'GOGO_BASE_URLS',
    'GOGO_BASE_URL',
    'https://gogoanime3.net',
  ),
  gogoAjaxUrl: (process.env.GOGO_AJAX_URL ?? 'https://ajax.gogo-load.com').replace(/\/$/, ''),
  samehadakuBaseUrls: urlList(
    'SAMEHADAKU_BASE_URLS',
    'SAMEHADAKU_BASE_URL',
    'https://v2.samehadaku.how,https://samehadaku.how',
  ),
  /** Mirror utama (pertama) — untuk display/meta saja. */
  get gogoBaseUrl(): string {
    return this.gogoBaseUrls[0];
  },
  get samehadakuBaseUrl(): string {
    return this.samehadakuBaseUrls[0];
  },
  nyaaBaseUrl: (process.env.NYAA_BASE_URL ?? 'https://nyaa.si').replace(/\/$/, ''),
  gogobyBaseUrl: (process.env.GOGOBY_BASE_URL ?? 'https://gogoanime.by').replace(/\/$/, ''),
  kitsuBaseUrl: (process.env.KITSU_BASE_URL ?? 'https://kitsu.io/api/edge').replace(/\/$/, ''),
  torrentioBaseUrl: (process.env.TORRENTIO_BASE_URL ?? 'https://torrentio.strem.fun').replace(
    /\/$/,
    '',
  ),
  /**
   * Kredensial client publik beta-API Crunchyroll (dipakai tool pihak ketiga,
   * bisa dicabut sewaktu-waktu — override via env bila punya sendiri).
   */
  crunchyrollBasicToken:
    process.env.CRUNCHYROLL_BASIC_TOKEN ??
    'dC1rZGdwMmg4YzNqdWI4Zm4wZnE6eWZMRGZNZnJZdktYaDRKWFMxTEVJMmNDcXUxdjVXYW4=',
  /** API key TorBox (akun gratis tersedia) — kosong = endpoint debrid nonaktif. */
  torboxApiKey: process.env.TORBOX_API_KEY ?? '',
  httpTimeoutMs: Number(process.env.HTTP_TIMEOUT_MS ?? 15000),
  cacheTtlSeconds: Number(process.env.CACHE_TTL_SECONDS ?? 300),
  rateWindowMs: Number(process.env.RATE_LIMIT_WINDOW_MS ?? 60_000),
  rateMax: Number(process.env.RATE_LIMIT_MAX ?? 120),
  corsOrigin: process.env.CORS_ORIGIN ?? '*',
};
