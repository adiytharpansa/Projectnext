import type {
  AnimeInfo,
  AnimeSearchResult,
  DownloadGroup,
  ProviderMeta,
  WatchData,
} from './types';

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const API_URL = (process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:3000').replace(/\/$/, '');

export function apiBase(): string {
  return API_URL;
}

interface Envelope<T> {
  success: boolean;
  status: number;
  message?: string;
  data: T;
}

async function get<T>(path: string): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, { cache: 'no-store' });
  } catch {
    throw new ApiError(0, 'Tidak dapat terhubung ke server API. Periksa NEXT_PUBLIC_API_URL & koneksi.');
  }
  let json: Envelope<T>;
  try {
    json = (await res.json()) as Envelope<T>;
  } catch {
    throw new ApiError(res.status, `Respons API tidak valid (HTTP ${res.status})`);
  }
  if (!res.ok || json.success === false) {
    throw new ApiError(json.status ?? res.status, json.message ?? `Error API (HTTP ${res.status})`);
  }
  return json.data;
}

/** GET /api/v1/anime/search — provider opsional; kosong = agregat semua. */
export async function searchAnime(
  query: string,
  provider?: string,
): Promise<{ query: string; count: number; results: AnimeSearchResult[] }> {
  const p = new URLSearchParams({ query });
  if (provider) p.set('provider', provider);
  return get(`/api/v1/anime/search?${p.toString()}`);
}

export async function fetchAnimeInfo(provider: string, id: string): Promise<AnimeInfo> {
  const p = new URLSearchParams({ provider, id });
  return get(`/api/v1/anime/info?${p.toString()}`);
}

export async function fetchWatchData(provider: string, episodeId: string): Promise<WatchData> {
  const p = new URLSearchParams({ provider, episodeId });
  return get(`/api/v1/anime/watch?${p.toString()}`);
}

export async function fetchDownloadGroups(
  provider: string,
  episodeId: string,
): Promise<{ provider: string; episodeId: string; count: number; groups: DownloadGroup[] }> {
  const p = new URLSearchParams({ provider, episodeId });
  return get(`/api/v1/anime/download?${p.toString()}`);
}

export async function fetchProviders(): Promise<ProviderMeta[]> {
  const data = await get<ProviderMeta[] | { providers: ProviderMeta[] }>('/api/v1/providers');
  return Array.isArray(data) ? data : data.providers;
}

// ── Debrid gratis (TorBox): magnet → HTTP ─────────────────

export type DebridState = 'ready' | 'pending' | 'downloading';

export interface DebridResult {
  provider: string;
  state: DebridState;
  torrentId?: number;
  streamUrl?: string;
  file?: { id: number; name: string; size: number };
  progress?: number;
  note?: string;
}

export interface DebridStatus {
  configured: boolean;
  provider: string;
  plan: string;
  limits: { maxSize: string; adds: string; slots: string };
  hint: string;
}

export async function debridStatus(): Promise<DebridStatus> {
  return get('/api/v1/debrid/status');
}

export async function unrestrictMagnet(magnet: string): Promise<DebridResult> {
  const res = await fetch(`${API_URL}/api/v1/debrid/unrestrict`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ magnet }),
    cache: 'no-store',
  });
  const json = (await res.json()) as Envelope<DebridResult>;
  if (!res.ok || json.success === false) {
    throw new ApiError(json.status ?? res.status, json.message ?? 'Debrid gagal');
  }
  return json.data;
}

export async function pollDebrid(torrentId: number): Promise<DebridResult> {
  return get(`/api/v1/debrid/torrent/${torrentId}`);
}

/**
 * Bangun URL streaming anti-gagal:
 *  - .m3u8 → lewat /api/proxy/m3u8 (rewrite segmen + suntik Referer)
 *  - file lain (mp4/vtt/ts) → lewat /api/proxy generik
 * Aman dipanggil dengan URL mentah dari backend.
 */
export function proxiedStreamUrl(rawUrl: string, referer?: string): string {
  const params = new URLSearchParams({ url: rawUrl });
  if (referer) params.set('referer', referer);
  const isHls = rawUrl.includes('.m3u8');
  return `${API_URL}/api/proxy${isHls ? '/m3u8' : ''}?${params.toString()}`;
}

/** Pilih source terbaik untuk player: hls > mp4 > embed. */
export function pickPlayable(sources: WatchData['sources']): WatchData['sources'][number] | undefined {
  return (
    sources.find((s) => s.type === 'hls' && !s.isEmbed) ??
    sources.find((s) => s.type === 'mp4' && !s.isEmbed) ??
    sources[0]
  );
}
