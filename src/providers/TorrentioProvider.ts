import { BaseProvider } from './BaseProvider';
import { httpClient } from '../services/httpClient';
import { appConfig } from '../config';
import { ApiError } from '../middlewares/errorHandler';
import { sortGroupsByResolution } from '../utils/quality';
import type {
  AnimeEpisode,
  AnimeInfo,
  AnimeSearchResult,
  DownloadGroup,
  DownloadLink,
  WatchData,
} from '../types';

interface KitsuAnime {
  id: string;
  attributes: {
    canonicalTitle?: string;
    synopsis?: string;
    posterImage?: { original?: string; large?: string };
    startDate?: string;
    showType?: string;
    episodeCount?: number;
    averageRating?: string;
    status?: string;
  };
  relationships?: {
    categories?: { links?: { related?: string } };
  };
}

interface TorrentioStream {
  infoHash?: string;
  title?: string;
  name?: string;
  behaviorHints?: { videoExtension?: string; filename?: string };
}

const TRACKERS = [
  'udp://tracker.opentrackr.org:1337/announce',
  'udp://open.stealth.si:80/announce',
  'udp://exodus.desync.com:6969/announce',
  'udp://tracker.torrent.eu.org:451/announce',
];

/** Bangun magnet dari infoHash + tracker publik. */
export function magnetFromHash(infoHash: string, name?: string): string {
  const tr = TRACKERS.map((t) => `&tr=${encodeURIComponent(t)}`).join('');
  return `magnet:?xt=urn:btih:${infoHash}${name ? `&dn=${encodeURIComponent(name)}` : ''}${tr}`;
}

/** Resolusi dari tag judul torrent. */
export function torrentResolution(title: string): string {
  const m = title.match(/(\d{3,4})\s*[pi]/i);
  return m ? `${m[1]}p` : 'default';
}

/** Nama grup/uploader = [Bracket] pertama, fallback nama file. */
export function torrentGroup(title: string): string {
  const m = title.match(/^\[([^\]]+)\]/);
  return m ? m[1] : 'Torrentio';
}

/** Jumlah seeder dari "👤 123" di judul Torrentio. */
export function torrentSeeders(title: string): number {
  const m = title.match(/👤\s*([\d,]+)/);
  return m ? Number(m[1].replace(/,/g, '')) || 0 : 0;
}

/**
 * Provider Torrentio — agregat torrent anime dari banyak indexer.
 * ID memakai Kitsu (kitsu.io, gratis tanpa kunci):
 *  search         → id "kitsu:<kid>"
 *  info/download  → episode "kitsu:<kid>:<ep>"
 *
 * Unduhan = magnet per resolusi. Streaming langsung tidak bisa
 * (butuh debrid) → fetchSources melempar error informatif.
 */
export class TorrentioProvider extends BaseProvider {
  readonly id = 'torrentio';
  readonly name = 'Torrentio';
  readonly languages = ['multi'];

  get baseUrl(): string {
    return appConfig.torrentioBaseUrl;
  }

  private async kitsuSearch(query: string): Promise<KitsuAnime[]> {
    const url = `${appConfig.kitsuBaseUrl}/anime?filter[text]=${encodeURIComponent(query)}&page[limit]=10`;
    try {
      const json = await httpClient.getJson<{ data?: KitsuAnime[] }>(url, {
        Accept: 'application/vnd.api+json',
      });
      return json.data ?? [];
    } catch (e) {
      throw ApiError.upstream(`Gagal mencari di Kitsu: ${(e as Error).message}`);
    }
  }

  private toResult(a: KitsuAnime): AnimeSearchResult {
    const at = a.attributes;
    return {
      id: `kitsu:${a.id}`,
      title: at.canonicalTitle ?? `Kitsu ${a.id}`,
      url: `https://kitsu.io/anime/${a.id}`,
      image: at.posterImage?.original ?? at.posterImage?.large ?? '',
      description: (at.synopsis ?? '').slice(0, 220) || undefined,
      releaseDate: at.startDate ?? undefined,
      type: at.showType ?? undefined,
      score: at.averageRating ?? undefined,
    };
  }

  // ── SEARCH (via Kitsu) ──────────────────────────────────
  async search(query: string): Promise<AnimeSearchResult[]> {
    const q = query.trim();
    if (!q) throw ApiError.badRequest('Query "query" wajib diisi');
    return this.cache.wrap(this.key('search', q.toLowerCase()), async () => {
      return (await this.kitsuSearch(q)).map((a) => this.toResult(a));
    });
  }

  private parseEpId(episodeId: string): { kid: string; ep: number } {
    const m = decodeURIComponent(episodeId).trim().match(/^kitsu:(\d+)(?::(\d+))?$/i);
    if (!m) {
      throw ApiError.badRequest(
        'Format ID Torrentio: "kitsu:<kitsuId>" (info) atau "kitsu:<kitsuId>:<episode>" (unduhan).',
      );
    }
    return { kid: m[1], ep: m[2] ? Number(m[2]) : 1 };
  }

  // ── INFO (via Kitsu) ────────────────────────────────────
  async fetchInfo(id: string): Promise<AnimeInfo> {
    const raw = decodeURIComponent(id).trim();
    const kid = raw.replace(/^kitsu:/i, '').split(':')[0];
    if (!/^kitsu:\d+$/i.test(raw) && !/^\d+$/.test(raw)) {
      throw ApiError.badRequest('Format ID Torrentio: "kitsu:<kitsuId>". Dapatkan dari endpoint search.');
    }
    return this.cache.wrap(this.key('info', kid), async () => {
      let json: { data?: KitsuAnime };
      try {
        json = await httpClient.getJson(
          `${appConfig.kitsuBaseUrl}/anime/${kid}?include=categories`,
          { Accept: 'application/vnd.api+json' },
        );
      } catch (e) {
        throw ApiError.upstream(`Gagal mengambil info Kitsu "${kid}": ${(e as Error).message}`);
      }
      const a = json.data;
      if (!a) throw ApiError.notFound(`Anime Kitsu "${kid}" tidak ditemukan`);
      const at = a.attributes;
      const count = at.episodeCount ?? 0;

      let genres: string[] | undefined;
      try {
        const rel = a.relationships?.categories?.links?.related;
        if (rel) {
          const cats = await httpClient.getJson<{ data?: { attributes?: { title?: string } }[] }>(rel, {
            Accept: 'application/vnd.api+json',
          });
          genres = (cats.data ?? [])
            .map((c) => c.attributes?.title)
            .filter((t): t is string => Boolean(t))
            .slice(0, 8);
          if (genres.length === 0) genres = undefined;
        }
      } catch {
        /* genre opsional */
      }

      const episodes: AnimeEpisode[] = [];
      for (let n = 1; n <= count; n++) {
        episodes.push({
          id: `kitsu:${kid}:${n}`,
          number: n,
          title: `Episode ${n}`,
          url: `https://kitsu.io/anime/${kid}/episodes/${n}`,
        });
      }
      return {
        id: `kitsu:${kid}`,
        title: at.canonicalTitle ?? `Kitsu ${kid}`,
        url: `https://kitsu.io/anime/${kid}`,
        image: at.posterImage?.original ?? at.posterImage?.large ?? '',
        description: at.synopsis,
        genres,
        status: at.status,
        type: at.showType,
        releaseDate: at.startDate,
        totalEpisodes: count,
        score: at.averageRating,
        episodes,
      };
    });
  }

  // ── DOWNLOAD (via Torrentio, grup per resolusi) ─────────
  async fetchDownloadLinks(episodeId: string): Promise<DownloadGroup[]> {
    const { kid, ep } = this.parseEpId(episodeId);
    return this.cache.wrap(this.key('download', `${kid}:${ep}`), async () => {
      let json: { streams?: TorrentioStream[] };
      try {
        json = await httpClient.getJson(
          `${this.baseUrl}/stream/anime/kitsu:${kid}:${ep}.json`,
          { Accept: 'application/json' },
        );
      } catch (e) {
        throw ApiError.upstream(`Gagal mengambil stream Torrentio: ${(e as Error).message}`);
      }
      const streams = (json.streams ?? []).filter((s) => s.infoHash);
      if (streams.length === 0) throw ApiError.notFound(`Torrent untuk kitsu:${kid}:${ep} tidak ditemukan`);

      const byRes = new Map<string, { link: DownloadLink; seeders: number }[]>();
      for (const s of streams) {
        const title = `${s.name ?? ''}\n${s.title ?? ''}`.trim();
        const res = torrentResolution(title);
        const server = `${torrentGroup(title)} 👤${torrentSeeders(title)}`;
        const magnet = magnetFromHash(s.infoHash!, s.behaviorHints?.filename || s.name);
        if (!byRes.has(res)) byRes.set(res, []);
        byRes.get(res)!.push({ link: { server, url: magnet }, seeders: torrentSeeders(title) });
      }
      const groups: DownloadGroup[] = [...byRes.entries()].map(([resolution, items]) => ({
        format: 'Torrent',
        resolution,
        links: items.sort((a, b) => b.seeders - a.seeders).map((i) => i.link),
      }));
      return sortGroupsByResolution(groups);
    });
  }

  async fetchSources(): Promise<WatchData> {
    throw ApiError.badRequest(
      'Torrentio hanya mengembalikan magnet (butuh client torrent / debrid). ' +
        'Gunakan endpoint POST /api/v1/debrid/unrestrict untuk mengubah magnet jadi link HTTP yang bisa di-stream.',
    );
  }
}
