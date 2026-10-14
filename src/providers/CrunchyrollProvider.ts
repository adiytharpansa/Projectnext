import { BaseProvider } from './BaseProvider';
import { httpClient } from '../services/httpClient';
import { appConfig } from '../config';
import { ApiError } from '../middlewares/errorHandler';
import type {
  AnimeEpisode,
  AnimeInfo,
  AnimeSearchResult,
  DownloadGroup,
  WatchData,
} from '../types';

interface CrToken {
  access_token: string;
  expires_in: number;
}

interface CrImage {
  source?: string;
}

interface CrItem {
  id?: string;
  title?: string;
  slug?: string;
  description?: string;
  images?: {
    poster_tall?: CrImage[][];
    poster_wide?: CrImage[][];
  };
}

/**
 * Provider Crunchyroll — METADATA ONLY (poster HD resmi, sinopsis, season).
 *
 * memakai beta-API publik (anonymous client_credentials, tanpa login).
 * Situs webnya diblokir Cloudflare untuk scraping server-side.
 *
 * Keterbatasan jujur: stream butuh akun + Widevine DRM → fetchSources /
 * fetchDownloadLinks sengaja melempar error informatif. Pasangan ideal:
 * info dari sini, unduhan dari Nyaa/Torrentio, streaming via debrid.
 */
export class CrunchyrollProvider extends BaseProvider {
  readonly id = 'crunchyroll';
  readonly name = 'Crunchyroll';
  readonly languages = ['en', 'id'];

  private readonly apiBase = 'https://beta-api.crunchyroll.com';
  private token: string | null = null;
  private tokenUntil = 0;

  get baseUrl(): string {
    return 'https://www.crunchyroll.com';
  }

  private async bearer(): Promise<string> {
    if (this.token && Date.now() < this.tokenUntil) return this.token;
    let json: CrToken;
    try {
      json = await httpClient.postFormJson<CrToken>(
        `${this.apiBase}/auth/v1/token`,
        { grant_type: 'client_credentials', scope: 'offline_access' },
        {
          Authorization: `Basic ${appConfig.crunchyrollBasicToken}`,
          'User-Agent': 'Crunchyroll/3.60.0 Android/13 okhttp/4.12.0',
        },
      );
    } catch (e) {
      throw ApiError.upstream(`Gagal otentikasi Crunchyroll: ${(e as Error).message}`);
    }
    if (!json.access_token) throw ApiError.upstream('Token Crunchyroll kosong (client ditolak?)');
    this.token = json.access_token;
    // refresh 1 jam sebelum kedaluwarsa
    this.tokenUntil = Date.now() + Math.max(60, (json.expires_in ?? 3600) - 3600) * 1000;
    return this.token;
  }

  private headers(token: string): Record<string, string> {
    return {
      Authorization: `Bearer ${token}`,
      'User-Agent': 'Crunchyroll/3.60.0 Android/13 okhttp/4.12.0',
    };
  }

  private posterOf(item: CrItem): string {
    const tall = item.images?.poster_tall?.flat().map((i) => i.source).filter(Boolean) ?? [];
    const wide = item.images?.poster_wide?.flat().map((i) => i.source).filter(Boolean) ?? [];
    return (tall[tall.length - 1] ?? wide[wide.length - 1] ?? '') as string;
  }

  // ── SEARCH ──────────────────────────────────────────────
  async search(query: string): Promise<AnimeSearchResult[]> {
    const q = query.trim();
    if (!q) throw ApiError.badRequest('Query "query" wajib diisi');
    return this.cache.wrap(this.key('search', q.toLowerCase()), async () => {
      const token = await this.bearer();
      let json: { data?: { type?: string; items?: CrItem[] }[] };
      try {
        json = await httpClient.getJson(
          `${this.apiBase}/content/v2/discover/search?q=${encodeURIComponent(q)}&n=12&locale=en-US`,
          this.headers(token),
        );
      } catch (e) {
        throw ApiError.upstream(`Gagal mencari di Crunchyroll: ${(e as Error).message}`);
      }
      const out: AnimeSearchResult[] = [];
      const seen = new Set<string>();
      for (const cat of json.data ?? []) {
        if (cat.type !== 'series' && cat.type !== 'movie_listing') continue;
        for (const it of cat.items ?? []) {
          if (!it.id || seen.has(it.id)) continue;
          seen.add(it.id);
          out.push({
            id: it.id,
            title: it.title ?? it.id,
            url: `https://www.crunchyroll.com/series/${it.id}`,
            image: this.posterOf(it),
            description: (it.description ?? '').slice(0, 220) || undefined,
            type: cat.type === 'movie_listing' ? 'Movie' : 'TV',
          });
        }
      }
      return out;
    });
  }

  // ── INFO ────────────────────────────────────────────────
  async fetchInfo(id: string): Promise<AnimeInfo> {
    const seriesId = decodeURIComponent(id).trim().split('/')[0];
    return this.cache.wrap(this.key('info', seriesId), async () => {
      const token = await this.bearer();
      let json: { data?: CrItem[] };
      try {
        json = await httpClient.getJson(
          `${this.apiBase}/content/v2/cms/series/${encodeURIComponent(seriesId)}?locale=en-US`,
          this.headers(token),
        );
      } catch (e) {
        throw ApiError.upstream(`Gagal mengambil info Crunchyroll "${seriesId}": ${(e as Error).message}`);
      }
      const item = json.data?.[0];
      if (!item?.id) throw ApiError.notFound(`Judul "${seriesId}" tidak ditemukan di Crunchyroll`);

      // Jumlah season (best-effort; episode per season butuh akun → kosong jujur)
      let totalSeasons = 0;
      try {
        const seasons = await httpClient.getJson<{ total?: number }>(
          `${this.apiBase}/content/v2/cms/series/${encodeURIComponent(seriesId)}/seasons?locale=en-US`,
          this.headers(token),
        );
        totalSeasons = seasons.total ?? 0;
      } catch {
        /* abaikan */
      }

      const episodes: AnimeEpisode[] = [];
      return {
        id: item.id,
        title: item.title ?? item.id,
        url: `https://www.crunchyroll.com/series/${item.id}`,
        image: this.posterOf(item),
        description: item.description,
        genres: undefined,
        status: undefined,
        type: 'TV',
        releaseDate: undefined,
        totalEpisodes: totalSeasons,
        episodes,
      };
    });
  }

  // ── WATCH / DOWNLOAD: tidak didukung (DRM + akun) ───────
  async fetchSources(): Promise<WatchData> {
    throw ApiError.badRequest(
      'Crunchyroll memakai Widevine DRM + akun login — tidak bisa di-stream via HLS biasa. ' +
        'Gunakan info/poster dari sini, lalu stream dari provider gogo/samehadaku atau torrent via endpoint debrid.',
    );
  }

  async fetchDownloadLinks(): Promise<DownloadGroup[]> {
    throw ApiError.badRequest(
      'Crunchyroll tidak menyediakan unduhan langsung. Gunakan provider nyaa/torrentio untuk unduhan.',
    );
  }
}
