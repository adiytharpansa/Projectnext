import * as cheerio from 'cheerio';
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

export interface NyaaTorrent {
  id: string;
  title: string;
  url: string;
  torrentUrl: string;
  magnet: string;
  size: string;
  date: string;
  seeders: number;
  leechers: number;
}

/** Ambil resolusi dari tag judul: [1080p], 720p, dst. */
export function nyaaResolution(title: string): string {
  const m = title.match(/(\d{3,4})\s*[pi]/i);
  return m ? `${m[1]}p` : 'default';
}

/** Grup fansub = teks [Bracket] pertama. */
export function nyaaFansub(title: string): string {
  const m = title.match(/^\[([^\]]+)\]/);
  return m ? m[1] : 'Nyaa';
}

function num(text: string): number {
  const n = Number(text.trim().replace(/,/g, ''));
  return Number.isFinite(n) ? n : 0;
}

/**
 * Provider Nyaa.si — UNDUHAN torrent anime (magnet + .torrent).
 * Kategori default Anime English-translated (1_2).
 *
 * Catatan jujur: Nyaa tidak punya halaman info anime → fetchInfo/fetchSources
 * melempar error informatif. Pasangan ideal: info dari Crunchyroll/Kitsu,
 * unduhan dari sini, streaming via endpoint debrid (magnet → HTTP).
 */
export class NyaaProvider extends BaseProvider {
  readonly id = 'nyaa';
  readonly name = 'Nyaa.si';
  readonly languages = ['en', 'multi'];

  get baseUrl(): string {
    return appConfig.nyaaBaseUrl;
  }

  /** Parse tabel hasil Nyaa → daftar torrent (dipakai search & download). */
  parseTable(html: string): NyaaTorrent[] {
    const $ = cheerio.load(html);
    const out: NyaaTorrent[] = [];
    $('table.torrent-list tbody tr').each((_, el) => {
      const row = $(el);
      // Anchor judul = link /view/ TANPA class .comments (link komentar muncul duluan bila ada)
      const titleA = row.find('td[colspan] a[href^="/view/"]:not(.comments)').first();
      const title = (titleA.attr('title') ?? titleA.text()).trim();
      const viewHref = titleA.attr('href') ?? '';
      if (!title || !viewHref) return;
      const id = viewHref.split('/view/').pop() ?? '';
      const torrentHref = row.find('a[href^="/download/"]').attr('href') ?? '';
      const magnet = (row.find('a[href^="magnet:"]').attr('href') ?? '').replace(/&amp;/g, '&');
      const tds = row.find('td.text-center');
      out.push({
        id,
        title,
        url: `${this.baseUrl}${viewHref}`,
        torrentUrl: torrentHref ? `${this.baseUrl}${torrentHref}` : '',
        magnet,
        size: tds.eq(1).text().trim(),
        date: tds.eq(2).text().trim(),
        seeders: num(tds.eq(3).text()),
        leechers: num(tds.eq(4).text()),
      });
    });
    // Seeder terbanyak dulu — yang sehat di atas.
    return out.sort((a, b) => b.seeders - a.seeders);
  }

  private async searchTorrents(query: string): Promise<NyaaTorrent[]> {
    const url = `${this.baseUrl}/?f=0&c=1_2&q=${encodeURIComponent(query)}`;
    let html: string;
    try {
      html = await httpClient.getText(url, { Referer: `${this.baseUrl}/` });
    } catch (e) {
      throw ApiError.upstream(`Gagal mencari di Nyaa.si: ${(e as Error).message}`);
    }
    if (!html.includes('torrent-list')) {
      throw ApiError.upstream('Respons Nyaa.si tak dikenal (tema berubah / diblokir?)');
    }
    return this.parseTable(html);
  }

  // ── SEARCH (torrent per query) ──────────────────────────
  async search(query: string): Promise<AnimeSearchResult[]> {
    const q = query.trim();
    if (!q) throw ApiError.badRequest('Query "query" wajib diisi');
    return this.cache.wrap(this.key('search', q.toLowerCase()), async () => {
      const torrents = await this.searchTorrents(q);
      return torrents.slice(0, 25).map((t) => ({
        id: t.title,
        title: t.title,
        url: t.url,
        image: '',
        releaseDate: t.date || undefined,
        type: `Torrent • 👤${t.seeders} • ${t.size}`,
      }));
    });
  }

  // ── DOWNLOAD (grup per resolusi, server = fansub) ───────
  async fetchDownloadLinks(episodeId: string): Promise<DownloadGroup[]> {
    const q = decodeURIComponent(episodeId).trim();
    if (!q) throw ApiError.badRequest('Parameter episodeId/query wajib diisi');
    return this.cache.wrap(this.key('download', q.toLowerCase()), async () => {
      const torrents = await this.searchTorrents(q);
      if (torrents.length === 0) throw ApiError.notFound(`Torrent untuk "${q}" tidak ditemukan`);
      const byRes = new Map<string, DownloadLink[]>();
      for (const t of torrents) {
        if (!t.magnet) continue;
        const res = nyaaResolution(t.title);
        const server = `${nyaaFansub(t.title)} 👤${t.seeders}`;
        if (!byRes.has(res)) byRes.set(res, []);
        const links = byRes.get(res)!;
        links.push({ server, url: t.magnet });
        if (t.torrentUrl) links.push({ server: `${nyaaFansub(t.title)} (.torrent)`, url: t.torrentUrl });
      }
      const groups: DownloadGroup[] = [...byRes.entries()].map(([resolution, links]) => ({
        format: 'Torrent',
        resolution,
        links,
      }));
      return sortGroupsByResolution(groups);
    });
  }

  async fetchInfo(): Promise<AnimeInfo> {
    throw ApiError.badRequest(
      'Nyaa.si hanya indeks torrent — tidak ada halaman info anime. Ambil info dari provider crunchyroll/torrentio/gogo.',
    );
  }

  async fetchSources(): Promise<WatchData> {
    throw ApiError.badRequest(
      'Torrent tidak bisa di-stream langsung. Gunakan endpoint POST /api/v1/debrid/unrestrict dengan magnet untuk mengubahnya jadi link HTTP.',
    );
  }
}
