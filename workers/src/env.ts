import { appConfig } from '../../src/config';
import { httpClient } from '../../src/services/httpClient';

// Paksa instance axios backend memakai Fetch adapter — default chain axios
// memilih node:http di nodejs_compat, yang justru melempar error di workerd.
// (Patch Request/fetch-nya sendiri ada di shim.ts yang dimuat lebih dulu.)
// Harus jalan sebelum provider mana pun dipakai.
httpClient.setAdapter('fetch');
httpClient.setFetchEnv({
  fetch: globalThis.fetch,
  Request: globalThis.Request,
  Response: globalThis.Response,
});

export interface WorkerEnv {
  TORBOX_API_KEY?: string;
  GOGO_BASE_URLS?: string;
  GOGO_AJAX_URL?: string;
  SAMEHADAKU_BASE_URLS?: string;
  NYAA_BASE_URL?: string;
  GOGOBY_BASE_URL?: string;
  KITSU_BASE_URL?: string;
  TORRENTIO_BASE_URL?: string;
  CRUNCHYROLL_BASIC_TOKEN?: string;
  CACHE_TTL_SECONDS?: string;
  RATE_LIMIT_MAX?: string;
  [key: string]: string | undefined;
}

function list(v: string | undefined): string[] {
  return (v ?? '')
    .split(',')
    .map((s) => s.trim().replace(/\/$/, ''))
    .filter(Boolean);
}

let applied = false;

/**
 * Terapkan wrangler [vars]/secrets ke appConfig backend (sekali per isolate).
 * Dipanggil dari middleware pertama — idempoten & murah.
 */
export function applyEnv(env: WorkerEnv): void {
  if (applied) return;
  applied = true;
  if (env.TORBOX_API_KEY) appConfig.torboxApiKey = env.TORBOX_API_KEY;
  const gogo = list(env.GOGO_BASE_URLS);
  if (gogo.length > 0) appConfig.gogoBaseUrls = gogo;
  if (env.GOGO_AJAX_URL) appConfig.gogoAjaxUrl = env.GOGO_AJAX_URL.replace(/\/$/, '');
  const sd = list(env.SAMEHADAKU_BASE_URLS);
  if (sd.length > 0) appConfig.samehadakuBaseUrls = sd;
  if (env.NYAA_BASE_URL) appConfig.nyaaBaseUrl = env.NYAA_BASE_URL.replace(/\/$/, '');
  if (env.GOGOBY_BASE_URL) appConfig.gogobyBaseUrl = env.GOGOBY_BASE_URL.replace(/\/$/, '');
  if (env.KITSU_BASE_URL) appConfig.kitsuBaseUrl = env.KITSU_BASE_URL.replace(/\/$/, '');
  if (env.TORRENTIO_BASE_URL) appConfig.torrentioBaseUrl = env.TORRENTIO_BASE_URL.replace(/\/$/, '');
  if (env.CRUNCHYROLL_BASIC_TOKEN) appConfig.crunchyrollBasicToken = env.CRUNCHYROLL_BASIC_TOKEN;
  if (env.CACHE_TTL_SECONDS) appConfig.cacheTtlSeconds = Number(env.CACHE_TTL_SECONDS) || 300;
  if (env.RATE_LIMIT_MAX) appConfig.rateMax = Number(env.RATE_LIMIT_MAX) || 120;
}
