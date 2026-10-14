import * as cheerio from 'cheerio';
import { BaseProvider } from './BaseProvider';
import { httpClient } from '../services/httpClient';
import { appConfig } from '../config';
import { ApiError } from '../middlewares/errorHandler';
import { joinUrl, normalizeUrl, slugFromUrl } from '../utils/url';
import { sortGroupsByResolution } from '../utils/quality';
import type {
  AnimeEpisode,
  AnimeInfo,
  AnimeSearchResult,
  DownloadGroup,
  DownloadLink,
  StreamSource,
  Subtitle,
  WatchData,
} from '../types';

/**
 * Provider Samehadaku (lokal/ID, subtitle Indonesia).
 *
 * Endpoint:
 *  search   GET {base}/?s=
 *  info     GET {base}/anime/:slug
 *  watch    GET {base}/:episode-slug (+ POST admin-ajax.php player_ajax)
 *  download GET {base}/:episode-slug (blok .download / .dlbox)
 *
 * Domain Samehadaku sering berganti — override via env SAMEHADAKU_BASE_URL.
 */
export class SamehadakuProvider extends BaseProvider {
  readonly id = 'samehadaku';
  readonly name = 'Samehadaku';
  readonly languages = ['id'];
  readonly aliases = ['samehadaku', 'sd'];

  get baseUrl(): string {
    return appConfig.samehadakuBaseUrl;
  }

  private headers(referer?: string): Record<string, string> {
    return {
      Referer: referer ?? `${this.baseUrl}/`,
      Origin: new URL(this.baseUrl).origin,
    };
  }

  // ── SEARCH ──────────────────────────────────────────────
  async search(query: string): Promise<AnimeSearchResult[]> {
    const q = query.trim();
    if (!q) throw ApiError.badRequest('Query "query" wajib diisi');
    return this.cache.wrap(this.key('search', q.toLowerCase()), async () => {
      const { base, html } = await this.fetchFromMirrors(
        appConfig.samehadakuBaseUrls,
        (b) => `${b}/?s=${encodeURIComponent(q)}`,
        (b) => this.headers(`${b}/`),
        (h) => h.includes('animpost') || h.includes('notfound'),
      );
      const $ = cheerio.load(html);
      if ($('main#main .notfound').length > 0) return [];
      const results: AnimeSearchResult[] = [];
      $('main#main article.animpost, article.animpost').each((_, el) => {
        const root = $(el);
        const linkEl = root.find('a').first();
        const href = linkEl.attr('href') ?? '';
        if (!href) return;
        const img = root.find('img').first();
        const genres: string[] = [];
        root
          .find('div.genres a, .mta a')
          .each((_, a) => {
            const g = $(a).text().trim();
            if (g) genres.push(g);
          });
        results.push({
          id: slugFromUrl(href),
          title: (img.attr('title') ?? linkEl.attr('title') ?? root.find('.ttls').text()).trim(),
          url: href.startsWith('http') ? href : joinUrl(base, href),
          image: normalizeUrl(base, img.attr('src') ?? img.attr('data-src')),
          score: root.find('div.score, .score').first().text().trim() || undefined,
          genres: genres.length ? genres : undefined,
          description: root.find('div.ttls').text().trim() || undefined,
          type: root.find('div.type').first().text().trim() || undefined,
        });
      });
      return results;
    });
  }

  // ── INFO ────────────────────────────────────────────────
  async fetchInfo(id: string): Promise<AnimeInfo> {
    const slug = slugFromUrl(decodeURIComponent(id).trim());
    return this.cache.wrap(this.key('info', slug), async () => {
      const { base, html } = await this.fetchFromMirrors(
        appConfig.samehadakuBaseUrls,
        (b) => `${b}/anime/${slug}/`,
        (b) => this.headers(`${b}/`),
        (h) => h.includes('infoanime'),
      );
      const $ = cheerio.load(html);
      const rawTitle = $('.infoanime h1[itemprop="name"], .infoanime > h1').first().text().trim();
      if (!rawTitle) throw ApiError.notFound(`Anime "${slug}" tidak ditemukan`);
      const title = rawTitle.replace(/^Nonton Anime\s+/i, '').trim();

      const image = normalizeUrl(
        base,
        $('.infoanime .thumb img, .infoanime img').first().attr('src'),
      );
      const description = $('.infox .desc, .desc').first().text().trim() || undefined;

      const genres: string[] = [];
      $('.infox .genre-info a, .genre-info a').each((_, a) => {
        const g = $(a).text().trim();
        if (g) genres.push(g);
      });

      const detail: Record<string, string> = {};
      $('h3.anim-detail')
        .next()
        .find('span')
        .each((_, el) => {
          const name = $(el).find('b').text().replace(':', '').trim().toLowerCase();
          const value = $(el).text().replace($(el).find('b').text(), '').trim();
          if (name) detail[name] = value;
        });

      const trailer =
        $('.trailer-anime iframe').attr('src') ?? $('.trailer iframe').attr('src') ?? undefined;
      const ratingValue = $('.infoanime [itemprop="ratingValue"]').first().text().trim();
      const ratingCount = $('.infoanime [itemprop="ratingCount"]').attr('content');
      const score = ratingValue
        ? ratingCount
          ? `${ratingValue}/${ratingCount}`
          : ratingValue
        : undefined;

      const batchUrl = $('.listbatch a').attr('href') ?? null;

      const episodes: AnimeEpisode[] = [];
      $('.lstepsiode ul li, .lstepsiode li').each((_, el) => {
        const a = $(el).find('.lchx a, .eps a, a').first();
        const href = a.attr('href') ?? '';
        if (!href) return;
        const epTitle = (a.text() || '').trim();
        const numMatch = epTitle.match(/episode\s*(\d+)/i);
        const number = numMatch ? Number(numMatch[1]) : episodes.length + 1;
        episodes.push({
          id: slugFromUrl(href),
          number,
          title: epTitle || `Episode ${number}`,
          url: href.startsWith('http') ? href : joinUrl(base, href),
          date: $(el).find('.date').text().trim() || undefined,
        });
      });
      episodes.sort((a, b) => a.number - b.number);

      return {
        id: slug,
        title,
        url: `${base}/anime/${slug}/`,
        image,
        description,
        genres,
        status: detail['status'],
        type: detail['type'] ?? detail['tipe'],
        releaseDate: detail['released'] ?? detail['rilis'],
        totalEpisodes: episodes.length,
        trailer,
        score,
        studios: detail['studio'] ? [detail['studio']] : undefined,
        episodes,
        batchUrl,
      };
    });
  }

  // ── WATCH ───────────────────────────────────────────────
  async fetchSources(episodeId: string): Promise<WatchData> {
    const slug = slugFromUrl(decodeURIComponent(episodeId).trim());
    return this.cache.wrap(this.key('watch', slug), async () => {
      const { base, html } = await this.fetchFromMirrors(
        appConfig.samehadakuBaseUrls,
        (b) => `${b}/${slug}/`,
        (b) => this.headers(`${b}/`),
        (h) =>
          h.includes('data-post') ||
          h.includes('id="server"') ||
          h.includes('class="download"') ||
          h.includes('dlbox'),
      );
      const pageUrl = `${base}/${slug}/`;
      const $ = cheerio.load(html);
      const title = $('h1[itemprop="name"]').first().text().trim() || slug;

      // Resolve tiap server via admin-ajax player_ajax
      const servers: { name: string; url: string }[] = [];
      const jobs: Promise<void>[] = [];
      $('div#server ul li').each((_, el) => {
        const box = $(el).find('div[data-post]');
        const name = $(el).find('span').first().text().trim() || 'Server';
        const post = box.attr('data-post') ?? '';
        const nume = box.attr('data-nume') ?? '';
        const type = box.attr('data-type') ?? '';
        if (!post) return;
        jobs.push(
          (async () => {
            try {
              const resHtml = await httpClient.postFormText(
                `${base}/wp-admin/admin-ajax.php`,
                { action: 'player_ajax', post, nume, type },
                this.headers(pageUrl),
              );
              const $$ = cheerio.load(resHtml);
              const src =
                $$('iframe').attr('src') ??
                $$('iframe').attr('data-src') ??
                $$('source').attr('src') ??
                '';
              if (src) {
                servers.push({
                  name,
                  url: src.startsWith('//') ? `https:${src}` : src,
                });
              }
            } catch {
              /* server individual gagal — lewati */
            }
          })(),
        );
      });
      await Promise.all(jobs);
      // Fallback: iframe inline bila ajax gagal total
      if (servers.length === 0) {
        $('iframe').each((_, el) => {
          const src = $(el).attr('src') ?? $(el).attr('data-src') ?? '';
          if (src && /blogger|filedon|pixeldrain|drive|stream|video/i.test(src)) {
            servers.push({
              name: 'embed',
              url: src.startsWith('//') ? `https:${src}` : src,
            });
          }
        });
      }

      const sources: StreamSource[] = [];
      const subtitles: Subtitle[] = [];
      // Coba ekstrak direct link dari tiap embed (blogger/filedon/pixeldrain/drive)
      for (const s of servers) {
        const direct = await this.tryResolveEmbed(s.url, pageUrl).catch(() => undefined);
        if (direct) {
          sources.push({ url: direct, type: direct.includes('.m3u8') ? 'hls' : 'mp4', quality: 'auto', server: s.name });
        }
      }
      if (sources.length === 0) {
        for (const s of servers) {
          sources.push({ url: s.url, type: 'embed', quality: 'auto', isEmbed: true, server: s.name });
        }
      }

      let download: DownloadGroup[] | undefined;
      try {
        const groups = this.parseDownloadBlock($);
        if (groups.length > 0) download = groups;
      } catch {
        download = undefined;
      }

      if (servers.length === 0 && (!download || download.length === 0)) {
        throw ApiError.notFound(`Stream/download untuk "${slug}" tidak ditemukan`);
      }

      return {
        episodeId: slug,
        title,
        embedUrl: servers[0]?.url,
        headers: { Referer: pageUrl, Origin: new URL(base).origin },
        sources,
        subtitles,
        servers: servers.length ? servers : undefined,
        download,
      };
    });
  }

  /** Coba resolve embed populer ke direct file (best-effort, banyak yg anti-hotlink). */
  private async tryResolveEmbed(embedUrl: string, referer: string): Promise<string | undefined> {
    if (!/^https?:\/\//i.test(embedUrl)) return undefined;
    // Pixeldrain: /api/file/{id} / /u/{id} -> https://pixeldrain.com/api/file/{id}
    const pd = embedUrl.match(/pixeldrain\.com\/(?:u|api\/file)\/([A-Za-z0-9]+)/);
    if (pd) return `https://pixeldrain.com/api/file/${pd[1]}`;
    // Blogger: halaman embed berisi <source src="...mp4"> / VIDEO_CONFIG
    if (/blogger\.com|\.googlevideo\.com|blogspot/i.test(embedUrl)) {
      const html = await httpClient.getText(embedUrl, { Referer: referer });
      const m =
        html.match(/<source[^>]+src="([^"]+)"/) ??
        html.match(/"(https:[^"]+\.googlevideo\.com[^"]+)"/);
      if (m) return m[1].replace(/\\u0026/g, '&').replace(/\\/g, '');
      return undefined;
    }
    return undefined;
  }

  // ── DOWNLOAD ────────────────────────────────────────────
  async fetchDownloadLinks(episodeId: string): Promise<DownloadGroup[]> {
    const slug = slugFromUrl(decodeURIComponent(episodeId).trim());
    return this.cache.wrap(this.key('download', slug), async () => {
      const { html } = await this.fetchFromMirrors(
        appConfig.samehadakuBaseUrls,
        (b) => `${b}/${slug}/`,
        (b) => this.headers(`${b}/`),
        (h) =>
          h.includes('data-post') ||
          h.includes('id="server"') ||
          h.includes('class="download"') ||
          h.includes('dlbox'),
      );
      const groups = this.parseDownloadBlock(cheerio.load(html));
      if (groups.length === 0) throw ApiError.notFound(`Link unduhan untuk "${slug}" tidak ditemukan`);
      return groups;
    });
  }

  /**
   * Parse blok unduhan Samehadaku. Struktur bervariasi antar tema, jadi:
   *  1. Cari container (.download, .dlbox, #download, .dl, .download-eps)
   *  2. Tiap <li> = satu format; label resolusi dari <strong>/<i>/<b>;
   *     link server dari <a>.
   *  3. Fallback: semua <a> di container dikelompokkan via teks resolusi terdekat.
   */
  private parseDownloadBlock($: cheerio.CheerioAPI): DownloadGroup[] {
    const groups: DownloadGroup[] = [];
    const containers = $('.download, .dlbox, #download, .dl, .download-eps, .eps-download');
    const push = (format: string | undefined, resolution: string, link: DownloadLink) => {
      let g = groups.find(
        (x) => x.resolution === resolution && (x.format ?? '') === (format ?? ''),
      );
      if (!g) {
        g = { format, resolution, links: [] };
        groups.push(g);
      }
      if (!g.links.some((l) => l.url === link.url)) g.links.push(link);
    };

    const scope = containers.length > 0 ? containers.find('li') : $('li');
    scope.each((_, li) => {
      const el = $(li);
      const anchors = el.find('a[href^="http"]');
      if (anchors.length === 0) return;
      const text = el.text();
      if (!/\d{3,4}\s*p|HD|4K|MP4|MKV/i.test(text)) return;
      const formatMatch = el.find('strong, b, h4, .format').first().text().trim().toUpperCase();
      const format = /MKV/.test(formatMatch)
        ? 'MKV'
        : /MP4/.test(formatMatch)
          ? 'MP4'
          : /MP4|MKV/i.test(text)
            ? text.match(/MP4|MKV/i)![0].toUpperCase()
            : undefined;
      // Resolusi bisa beberapa per <li> ("360p | 480p ..."); pecah per segmen bila memungkinkan
      const resLabels = [...text.matchAll(/(\d{3,4})\s*p/gi)].map((m) => `${m[1]}p`);
      const fallbackRes = resLabels[0] ?? (/4K/i.test(text) ? '2160p' : 'default');
      anchors.each((_, a) => {
        const url = ($(a).attr('href') ?? '').trim();
        if (!url) return;
        // Tentukan resolusi anchor: label resolusi terdekat sebelumnya dalam teks li
        const before = text.slice(0, text.indexOf($(a).text()));
        const near = [...before.matchAll(/(\d{3,4})\s*p/gi)].pop();
        const resolution = near ? `${near[1]}p` : fallbackRes;
        const server = ($(a).text() || this.hostShort(url)).trim();
        push(format, resolution, { server, url });
      });
    });

    return sortGroupsByResolution(groups);
  }

  private hostShort(url: string): string {
    try {
      return new URL(url).hostname.replace(/^www\./, '');
    } catch {
      return 'Mirror';
    }
  }
}
