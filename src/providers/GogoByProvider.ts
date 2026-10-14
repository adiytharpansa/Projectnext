import * as cheerio from 'cheerio';
import { BaseProvider } from './BaseProvider';
import { httpClient } from '../services/httpClient';
import { appConfig } from '../config';
import { ApiError } from '../middlewares/errorHandler';
import { joinUrl, normalizeUrl, slugFromUrl } from '../utils/url';
import type {
  AnimeEpisode,
  AnimeInfo,
  AnimeSearchResult,
  DownloadGroup,
  StreamSource,
  Subtitle,
  WatchData,
} from '../types';

interface MegaSource {
  status?: string;
  source?: string;
  tracks?: { file?: string; label?: string; kind?: string }[];
}

/**
 * Provider gogoanime.by — klon Gogo bertema WordPress (dramastream/tsAnime).
 * Rantai stream terverifikasi:
 *  halaman episode → li.player-type-link[data-src] (/player/?source=embed&url=…)
 *  → iframe megavid.buzz → #player-payload {sourceUrl} → JSON {source: .m3u8, tracks[]}
 *
 * Tidak ada blok unduhan di tema ini → fetchDownloadLinks melempar error jujur.
 */
export class GogoByProvider extends BaseProvider {
  readonly id = 'gogoby';
  readonly name = 'Gogoanime.by';
  readonly languages = ['en'];

  get baseUrl(): string {
    return appConfig.gogobyBaseUrl;
  }

  private headers(referer: string): Record<string, string> {
    return { Referer: referer, Origin: new URL(this.baseUrl).origin };
  }

  // ── SEARCH (?s= → .listupd article.bs) ──────────────────
  async search(query: string): Promise<AnimeSearchResult[]> {
    const q = query.trim();
    if (!q) throw ApiError.badRequest('Query "query" wajib diisi');
    return this.cache.wrap(this.key('search', q.toLowerCase()), async () => {
      const { base, html } = await this.fetchFromMirrors(
        [this.baseUrl],
        (b) => `${b}/?s=${encodeURIComponent(q)}`,
        (b) => this.headers(`${b}/`),
        (h) => h.includes('listupd') || h.includes('notfound') || h.includes('No results'),
      );
      const $ = cheerio.load(html);
      const results: AnimeSearchResult[] = [];
      $('.listupd article.bs, article.bs').each((_, el) => {
        const a = $(el).find('.bsx a').first();
        const href = a.attr('href') ?? '';
        if (!href || !href.includes('/series/')) return;
        const img = a.find('img').first();
        results.push({
          id: slugFromUrl(href),
          title: (a.attr('title') ?? a.text()).trim(),
          url: href.startsWith('http') ? href : joinUrl(base, href),
          image: normalizeUrl(base, img.attr('src') ?? img.attr('data-src')),
          type: $(el).find('.typez').first().text().trim() || undefined,
          releaseDate: undefined,
        });
      });
      return results;
    });
  }

  // ── INFO (/series/:slug/ → .episode-item) ───────────────
  async fetchInfo(id: string): Promise<AnimeInfo> {
    const slug = slugFromUrl(decodeURIComponent(id).trim());
    return this.cache.wrap(this.key('info', slug), async () => {
      const { base, html } = await this.fetchFromMirrors(
        [this.baseUrl],
        (b) => `${b}/series/${slug}/`,
        (b) => this.headers(`${b}/`),
        (h) => h.includes('entry-title') && h.includes('episode-item'),
      );
      const $ = cheerio.load(html);
      const title = $('h1.entry-title').first().text().trim();
      if (!title) throw ApiError.notFound(`Anime "${slug}" tidak ditemukan`);
      const image = normalizeUrl(base, $('.thumb img').first().attr('src'));
      const description = $('.ninfo p, .entry-content p').first().text().trim() || undefined;

      const meta: Record<string, string> = {};
      $('.spe span').each((_, el) => {
        const name = $(el).find('b').text().replace(':', '').trim().toLowerCase();
        const value = $(el).text().replace($(el).find('b').text(), '').trim();
        if (name) meta[name] = value;
      });
      const genres: string[] = [];
      $('.genxed a').each((_, a) => {
        const g = $(a).text().trim();
        if (g) genres.push(g);
      });

      const episodes: AnimeEpisode[] = [];
      $('.episode-item[data-episode-number] a').each((_, el) => {
        const href = $(el).attr('href') ?? '';
        if (!href) return;
        const num = Number($(el).closest('.episode-item').attr('data-episode-number'));
        const epId = slugFromUrl(href);
        episodes.push({
          id: epId,
          number: Number.isFinite(num) ? num : episodes.length + 1,
          title: ($(el).text() || '').trim() || `Episode ${num}`,
          url: href.startsWith('http') ? href : joinUrl(base, href),
        });
      });
      episodes.sort((a, b) => a.number - b.number);

      return {
        id: slug,
        title,
        url: `${base}/series/${slug}/`,
        image,
        description,
        genres,
        status: meta['status'],
        type: meta['type'],
        releaseDate: meta['released'],
        totalEpisodes: episodes.length,
        episodes,
      };
    });
  }

  // ── WATCH (server → /player/ → megavid payload → m3u8) ──
  async fetchSources(episodeId: string): Promise<WatchData> {
    const slug = slugFromUrl(decodeURIComponent(episodeId).trim());
    return this.cache.wrap(this.key('watch', slug), async () => {
      const { base, html } = await this.fetchFromMirrors(
        [this.baseUrl],
        (b) => `${b}/${slug}/`,
        (b) => this.headers(`${b}/`),
        (h) => h.includes('w-servers') || h.includes('player-type-link'),
      );
      const pageUrl = `${base}/${slug}/`;
      const $ = cheerio.load(html);
      const title = $('h1.entry-title').first().text().trim() || slug;

      const servers: { name: string; url: string }[] = [];
      $('#w-servers .type').each((_, block) => {
        const kind = ($(block).attr('data-type') ?? '').toUpperCase();
        $(block)
          .find('li.player-type-link[data-src]')
          .each((_, li) => {
            const src = ($(li).attr('data-src') ?? '').trim();
            if (!src) return;
            const label = ($(li).text() || '').trim() || 'Server';
            servers.push({
              name: kind ? `${label} (${kind})` : label,
              url: src.startsWith('http') ? src : joinUrl(base, src),
            });
          });
      });
      // Fallback: iframe langsung bila tema berubah
      if (servers.length === 0) {
        $('iframe[src*="player"], iframe[src*="megavid"], iframe[src*="embed"]').each((_, el) => {
          const src = $(el).attr('src') ?? '';
          if (src) servers.push({ name: 'embed', url: src.startsWith('http') ? src : joinUrl(base, src) });
        });
      }
      if (servers.length === 0) throw ApiError.notFound(`Server stream "${slug}" tidak ditemukan`);

      const sources: StreamSource[] = [];
      const subtitles: Subtitle[] = [];
      for (const s of servers) {
        try {
          const found = await this.resolveServer(s.url, pageUrl);
          sources.push({ url: found.source, type: 'hls', quality: 'auto', server: s.name });
          for (const t of found.tracks) {
            if (t.file) subtitles.push({ url: t.file, lang: t.label ?? 'en', label: t.label });
          }
          break; // server pertama yang berhasil cukup
        } catch {
          /* coba server berikut */
        }
      }
      if (sources.length === 0) {
        // Semua gagal di-resolve → kembalikan embed pertama apa adanya
        sources.push({ url: servers[0].url, type: 'embed', quality: 'auto', isEmbed: true, server: servers[0].name });
      }

      return {
        episodeId: slug,
        title,
        embedUrl: servers[0].url,
        headers: { Referer: pageUrl, Origin: new URL(base).origin },
        sources,
        subtitles,
        servers,
      };
    });
  }

  /** /player/ → iframe embed → #player-payload → JSON {source, tracks}. */
  private async resolveServer(
    playerUrl: string,
    referer: string,
  ): Promise<{ source: string; tracks: { file?: string; label?: string }[] }> {
    const playerHtml = await httpClient.getText(playerUrl, this.headers(referer));
    const $ = cheerio.load(playerHtml);
    let embed = $('iframe.player-iframe').attr('src') ?? $('iframe').first().attr('src') ?? '';
    if (!embed) {
      const m = playerHtml.match(/src="(https?:[^"]+)"/);
      embed = m ? m[1] : '';
    }
    if (!embed) throw new Error('iframe player tidak ditemukan');
    if (embed.startsWith('//')) embed = `https:${embed}`;

    const embedHtml = await httpClient.getText(embed, this.headers(playerUrl));
    const payloadMatch = embedHtml.match(/<script[^>]*id="player-payload"[^>]*>([\s\S]*?)<\/script>/);
    if (!payloadMatch) throw new Error('player-payload tidak ditemukan');
    const payload = JSON.parse(payloadMatch[1]) as { sourceUrl?: string };
    if (!payload.sourceUrl) throw new Error('sourceUrl kosong');
    const origin = new URL(embed).origin;
    const sourceUrl = payload.sourceUrl.startsWith('http')
      ? payload.sourceUrl
      : `${origin}${payload.sourceUrl}`;

    const json = await httpClient.getJson<MegaSource>(sourceUrl, {
      ...this.headers(embed),
      Accept: 'application/json',
    });
    if (json.status !== 'ok' || !json.source) throw new Error('source HLS kosong');
    return { source: json.source, tracks: json.tracks ?? [] };
  }

  async fetchDownloadLinks(): Promise<DownloadGroup[]> {
    throw ApiError.badRequest(
      'Tema gogoanime.by tidak menyediakan blok unduhan. Gunakan provider nyaa/torrentio untuk unduhan.',
    );
  }
}
