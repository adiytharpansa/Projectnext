import { BaseProvider } from './BaseProvider';
import { httpClient } from '../services/httpClient';
import { ApiError } from '../middlewares/errorHandler';
import type {
  AnimeEpisode,
  AnimeInfo,
  AnimeSearchResult,
  DownloadGroup,
  WatchData,
} from '../types';

interface IqiyiVideo {
  itemTitle?: string;
  itemNumber?: number;
  itemVImage?: string;
  itemLink?: string;
  timeLength?: number;
  tvId?: number;
}

interface IqiyiAlbum {
  albumId?: number;
  albumTitle?: string;
  albumEnglishTitle?: string;
  albumLink?: string;
  albumVImage?: string;
  albumHImage?: string;
  director?: string;
  star?: string;
  region?: string;
  releaseDate?: string | number;
  tag?: string;
  itemTotalNumber?: number;
  score?: number;
  series?: boolean;
  channel?: string;
  threeCategory?: string;
  tvFocus?: string;
  siteId?: string;
  videoinfos?: IqiyiVideo[];
}

const SEARCH_API = 'https://search.video.iqiyi.com/o?if=html5&key=';
const MAX_SYNTH_EPISODES = 500;

function https(url: string | undefined): string {
  if (!url) return '';
  return url.replace(/^http:\/\//i, 'https://');
}

function fmtDate(raw: string | number | undefined): string | undefined {
  const s = String(raw ?? '');
  const m = s.match(/^(\d{4})(\d{2})(\d{2})$/);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : undefined;
}

function genresOf(a: IqiyiAlbum): string[] | undefined {
  // threeCategory: "剧情,127,2 动画,12,2 ..." → ambil nama tag-nya saja
  const tags = (a.threeCategory ?? '')
    .split(/\s+/)
    .map((t) => t.split(',')[0])
    .filter(Boolean)
    .slice(0, 6);
  return tags.length > 0 ? tags : undefined;
}

/**
 * Provider iQIYI — METADATA ONLY (search publik tanpa kunci, siteId=iqiyi).
 *
 * Endpoint playback butuh signature + akun + Widevine DRM → fetchSources /
 * fetchDownloadLinks sengaja melempar error informatif.
 * Info episode diambil dari cache hasil search (videoinfos ≤20 + sintesis
 * nomor sampai itemTotalNumber) karena API detail album butuh signature.
 */
export class IqiyiProvider extends BaseProvider {
  readonly id = 'iqiyi';
  readonly name = 'iQIYI';
  readonly languages = ['zh', 'en', 'id'];

  get baseUrl(): string {
    return 'https://www.iq.com';
  }

  private async searchAlbums(query: string): Promise<IqiyiAlbum[]> {
    let json: { data?: { docinfos?: { albumDocInfo?: IqiyiAlbum }[] } };
    try {
      json = await httpClient.getJson(`${SEARCH_API}${encodeURIComponent(query)}`, {
        Accept: 'application/json',
      });
    } catch (e) {
      throw ApiError.upstream(`Gagal mencari di iQIYI: ${(e as Error).message}`);
    }
    const docs = (json.data as unknown as { docinfos?: { albumDocInfo?: IqiyiAlbum }[] })?.docinfos;
    if (!Array.isArray(docs)) return [];
    // Hanya konten iQIYI sendiri (hasil campur youku/qq = platform lain)
    // + hanya album asli (film/series punya itemTotalNumber; klip pendek tidak)
    return docs
      .map((d) => d.albumDocInfo)
      .filter(
        (a): a is IqiyiAlbum =>
          Boolean(a && a.albumId && a.siteId === 'iqiyi' && a.itemTotalNumber !== undefined && a.itemTotalNumber !== null),
      );
  }

  private toResult(a: IqiyiAlbum): AnimeSearchResult {
    return {
      id: String(a.albumId),
      title: a.albumEnglishTitle || a.albumTitle || `iQIYI ${a.albumId}`,
      url: a.albumLink ? https(a.albumLink) : `https://www.iq.com/album/${a.albumId}`,
      image: https(a.albumVImage ?? a.albumHImage),
      description: a.tvFocus || (a.tag ?? '').split(/\s+/).slice(0, 12).join(' ') || undefined,
      releaseDate: fmtDate(a.releaseDate),
      type: a.series || (a.itemTotalNumber ?? 0) > 1 ? 'TV' : 'Movie',
      score: a.score !== undefined ? String(a.score) : undefined,
    };
  }

  // ── SEARCH ──────────────────────────────────────────────
  async search(query: string): Promise<AnimeSearchResult[]> {
    const q = query.trim();
    if (!q) throw ApiError.badRequest('Query "query" wajib diisi');
    return this.cache.wrap(this.key('search', q.toLowerCase()), async () => {
      const albums = await this.searchAlbums(q);
      // Simpan mentah untuk info (TTL cache standar)
      for (const a of albums) {
        this.cache.set(this.key('album', String(a.albumId)), a, 3600);
      }
      return albums.map((a) => this.toResult(a));
    });
  }

  // ── INFO (dari cache search) ────────────────────────────
  async fetchInfo(id: string): Promise<AnimeInfo> {
    const albumId = decodeURIComponent(id).trim().split(':').pop() ?? '';
    if (!/^\d+$/.test(albumId)) {
      throw ApiError.badRequest('Format ID iQIYI: "<albumId>" numerik dari endpoint search.');
    }
    return this.cache.wrap(this.key('info', albumId), async () => {
      const a = this.cache.get<IqiyiAlbum>(this.key('album', albumId));
      if (!a) {
        throw ApiError.notFound(
          `Album ${albumId} belum di-cache. Panggil /anime/search?query=... dulu, lalu buka info dari hasilnya.`,
        );
      }
      const total = Math.min(a.itemTotalNumber ?? 0, MAX_SYNTH_EPISODES);
      const byNum = new Map<number, IqiyiVideo>();
      for (const v of a.videoinfos ?? []) {
        if (v.itemNumber !== undefined) byNum.set(v.itemNumber, v);
      }
      const episodes: AnimeEpisode[] = [];
      const n = Math.max(total, byNum.size);
      for (let i = 1; i <= n; i++) {
        const v = byNum.get(i);
        episodes.push({
          id: `iqiyi:${albumId}:${i}`,
          number: i,
          title: v?.itemTitle || `Episode ${i}`,
          url: v?.itemLink ? https(v.itemLink) : `https://www.iq.com/album/${albumId}`,
        });
      }
      return {
        id: String(albumId),
        title: a.albumEnglishTitle || a.albumTitle || `iQIYI ${albumId}`,
        url: a.albumLink ? https(a.albumLink) : `https://www.iq.com/album/${albumId}`,
        image: https(a.albumVImage ?? a.albumHImage),
        description: a.tvFocus ?? a.tag ?? undefined,
        genres: genresOf(a),
        status: undefined,
        type: a.series || (a.itemTotalNumber ?? 0) > 1 ? 'TV' : 'Movie',
        releaseDate: fmtDate(a.releaseDate),
        totalEpisodes: n,
        score: a.score !== undefined ? String(a.score) : undefined,
        episodes,
      };
    });
  }

  async fetchSources(): Promise<WatchData> {
    throw ApiError.badRequest(
      'Playback iQIYI butuh signature + akun + Widevine DRM — tidak bisa di-stream via HLS biasa. ' +
        'Gunakan info/poster dari sini, stream dari gogo/gogoby, torrent via nyaa/torrentio + debrid.',
    );
  }

  async fetchDownloadLinks(): Promise<DownloadGroup[]> {
    throw ApiError.badRequest(
      'iQIYI tidak menyediakan unduhan langsung. Gunakan provider nyaa/torrentio untuk unduhan.',
    );
  }
}
