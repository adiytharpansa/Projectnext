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
 * Provider Gogoanime (global/EN).
 *
 * Endpoint:
 *  search   GET {base}/search.html?keyword=
 *  info     GET {base}/category/:slug  (+ ajax load-list-episode)
 *  watch    GET {base}/:episodeId  -> iframe embed (vidstream/gogoplay) -> m3u8/mp4
 *  download GET {base}/:episodeId  -> div.cf-download a
 *
 * Domain Gogo sering berganti — override via env GOGO_BASE_URL / GOGO_AJAX_URL.
 */
export class GogoanimeProvider extends BaseProvider {
  readonly id = 'gogo';
  readonly name = 'Gogoanime';
  readonly languages = ['en'];
  readonly aliases = ['gogoanime', 'anitaku'];

  get baseUrl(): string {
    return appConfig.gogoBaseUrl;
  }
  private get ajaxUrl(): string {
    return appConfig.gogoAjaxUrl;
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
        appConfig.gogoBaseUrls,
        (b) => `${b}/search.html?keyword=${encodeURIComponent(q)}`,
        (b) => this.headers(`${b}/`),
        (h) => h.includes('class="items"') || /no (anime|result)s? found|not found/i.test(h),
      );
      const $ = cheerio.load(html);
      const results: AnimeSearchResult[] = [];
      $('ul.items > li, div.items > li, .items li').each((_, el) => {
        const root = $(el);
        const anchor = root.find('.name a').first();
        const href = anchor.attr('href') ?? '';
        if (!href) return;
        const cleanId = href.includes('/category/')
          ? href.split('/category/').pop()!.replace(/\/$/, '')
          : slugFromUrl(href);
        const img = root.find('.img img').first();
        results.push({
          id: cleanId,
          title: (anchor.attr('title') ?? anchor.text()).trim(),
          url: joinUrl(base, href.startsWith('/') ? href : `/category/${cleanId}`),
          image: normalizeUrl(base, img.attr('src')),
          releaseDate: root.find('.released').text().replace('Released:', '').trim() || undefined,
          type: undefined,
        });
      });
      return results;
    });
  }

  // ── INFO ────────────────────────────────────────────────
  async fetchInfo(id: string): Promise<AnimeInfo> {
    const slug = this.normalizeInfoId(id);
    return this.cache.wrap(this.key('info', slug), async () => {
      const { base, html } = await this.fetchFromMirrors(
        appConfig.gogoBaseUrls,
        (b) => `${b}/category/${slug}`,
        (b) => this.headers(`${b}/`),
        (h) => h.includes('anime_info_body_bg'),
      );
      const $ = cheerio.load(html);
      const title = $('.anime_info_body_bg h1').first().text().trim();
      if (!title) throw ApiError.notFound(`Anime "${slug}" tidak ditemukan`);

      const image = normalizeUrl(base, $('.anime_info_body_bg img').first().attr('src'));

      // p.type blocks: "Type: ...", "Plot Summary: ...", "Genre: ...", "Released: ...", "Status: ...", "Other name: ..."
      const meta: Record<string, string> = {};
      const genres: string[] = [];
      const otherNames: string[] = [];
      $('div.anime_info_body_bg p.type').each((_, el) => {
        const label = $(el).find('span').first().text().replace(':', '').trim().toLowerCase();
        const full = $(el).text().trim();
        const value = full.replace(/^[^:]+:\s*/, '').trim();
        if (label) meta[label] = value;
        if (label === 'genre') {
          $(el)
            .find('a')
            .each((_, a) => {
              const g = $(a).text().trim();
              if (g) genres.push(g);
            });
        }
        if (label === 'other name' && value) {
          value
            .split(/[,;]/)
            .map((s) => s.trim())
            .filter(Boolean)
            .forEach((n) => otherNames.push(n));
        }
      });

      const episodes = await this.fetchEpisodeList($, slug, base);

      return {
        id: slug,
        title,
        url: `${base}/category/${slug}`,
        image,
        description: meta['plot summary'],
        genres,
        status: meta['status'],
        type: meta['type'],
        releaseDate: meta['released'],
        totalEpisodes: episodes.length,
        otherNames,
        episodes,
      };
    });
  }

  private normalizeInfoId(id: string): string {
    const s = decodeURIComponent(id).trim().replace(/\/$/, '');
    if (s.includes('/category/')) return s.split('/category/').pop()!;
    if (s.startsWith('category/')) return s.replace(/^category\//, '');
    return slugFromUrl(s);
  }

  private async fetchEpisodeList(
    $: cheerio.CheerioAPI,
    slug: string,
    base: string,
  ): Promise<AnimeEpisode[]> {
    const epStart = $('#episode_page a').first().attr('ep_start') ?? '1';
    const epEnd = $('#episode_page a').last().attr('ep_end');
    const movieId = $('input#movie_id').attr('value') ?? '';
    const alias = slug;

    // Fallback: episode ter-render langsung di HTML
    if (!epEnd || !movieId) {
      const direct: AnimeEpisode[] = [];
      $('#episode_related a, .episode_list a, ul#episode_page a').each((_, el) => {
        const href = $(el).attr('href') ?? '';
        const m = href.match(/-episode-(\d+)\/?$/);
        if (!m) return;
        const num = Number(m[1]);
        const epId = slugFromUrl(href);
        direct.push({
          id: epId,
          number: num,
          title: `Episode ${num}`,
          url: joinUrl(base, href),
        });
      });
      return direct.sort((a, b) => a.number - b.number);
    }

    const ajaxUrl =
      `${this.ajaxUrl}/ajax/load-list-episode` +
      `?ep_start=${epStart}&ep_end=${epEnd}&id=${movieId}&default_ep=0&alias=${encodeURIComponent(alias)}`;
    let listHtml: string;
    try {
      listHtml = await httpClient.getText(ajaxUrl, this.headers(`${base}/category/${slug}`));
    } catch {
      return [];
    }
    const $$ = cheerio.load(listHtml);
    const episodes: AnimeEpisode[] = [];
    $$('#episode_related a, li a').each((_, el) => {
      const href = $$(el).attr('href')?.trim() ?? '';
      if (!href) return;
      const epId = slugFromUrl(href);
      const nameText = $$(el).find('.name').text().trim() || $$(el).text().trim();
      const m = epId.match(/-episode-(\d+)$/) ?? nameText.match(/EP\s*(\d+)/i);
      const num = m ? Number(m[1]) : episodes.length + 1;
      episodes.push({
        id: epId,
        number: num,
        title: `Episode ${num}`,
        url: joinUrl(base, href.startsWith('/') ? href : `/${href}`),
      });
    });
    return episodes.sort((a, b) => a.number - b.number);
  }

  // ── WATCH ───────────────────────────────────────────────
  async fetchSources(episodeId: string): Promise<WatchData> {
    const epSlug = slugFromUrl(decodeURIComponent(episodeId).trim());
    if (!/-episode-\d+$/i.test(epSlug)) {
      throw ApiError.badRequest(
        'episodeId tidak valid. Contoh: "naruto-episode-10". Dapatkan dari endpoint info.',
      );
    }
    return this.cache.wrap(this.key('watch', epSlug), async () => {
      const { base, html } = await this.fetchFromMirrors(
        appConfig.gogoBaseUrls,
        (b) => `${b}/${epSlug}`,
        (b) => this.headers(`${b}/`),
        (h) => h.includes('load_anime') || h.includes('cf-download') || h.includes('anime_video_body'),
      );
      const $ = cheerio.load(html);
      const title = $('.anime-info a, .anime_video_body h1').first().text().trim() || epSlug;

      // 1) Cari embed URL
      let embedUrl =
        $('#load_anime iframe').attr('src') ??
        $('.play-video iframe').attr('src') ??
        $('iframe').first().attr('src') ??
        $('li.anime a').attr('data-video') ??
        '';
      embedUrl = embedUrl.trim();
      if (embedUrl.startsWith('//')) embedUrl = `https:${embedUrl}`;

      // 2) Kumpulkan server alternatif dari tab server
      const servers: { name: string; url: string }[] = [];
      $('div.anime_muti_link ul li a, .anime_muti_link a').each((_, el) => {
        const name = $(el).text().trim() || $(el).attr('data-video')?.slice(0, 24) || 'server';
        const dv = $(el).attr('data-video') ?? '';
        if (dv) servers.push({ name, url: dv.startsWith('//') ? `https:${dv}` : dv });
      });
      if (embedUrl) servers.unshift({ name: 'default', url: embedUrl });

      // 3) Coba resolve embed -> direct sources
      const sources: StreamSource[] = [];
      const subtitles: Subtitle[] = [];
      if (embedUrl && /^https?:\/\//i.test(embedUrl)) {
        try {
          const embedHtml = await httpClient.getText(
            embedUrl,
            this.headers(`${base}/${epSlug}`),
          );
          this.extractEmbedSources(embedHtml, embedUrl, sources, subtitles);
        } catch {
          // embed gagal di-resolve (crypto/anti-bot) — tetap kembalikan embed
        }
      }

      // 4) Fallback: regex langsung di halaman episode (kadang ada .m3u8 inline)
      if (sources.length === 0) {
        this.extractEmbedSources(html, `${base}/${epSlug}`, sources, subtitles);
      }

      if (sources.length === 0 && embedUrl) {
        const host = this.hostOf(embedUrl);
        sources.push({
          url: embedUrl,
          type: 'embed',
          quality: 'auto',
          isEmbed: true,
          server: this.serverName(host),
        });
      }

      // 5) Download links sekalian (Gogo menaruhnya di halaman yg sama)
      let download: DownloadGroup[] | undefined;
      try {
        download = this.parseDownloadBlock($);
        if (download.length === 0) download = undefined;
      } catch {
        download = undefined;
      }

      return {
        episodeId: epSlug,
        title,
        embedUrl: embedUrl || undefined,
        headers: {
          Referer: embedUrl || `${base}/`,
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
        sources,
        subtitles,
        servers: servers.length ? servers : undefined,
        download,
      };
    });
  }

  /** Ekstrak sources + subtitle dari HTML embed player (gogoplay/vidstream & generik). */
  private extractEmbedSources(
    html: string,
    pageUrl: string,
    sources: StreamSource[],
    subtitles: Subtitle[],
  ): void {
    const seen = new Set(sources.map((s) => s.url));

    // Pola 1: JSON "sources": [{file, label, type}]
    const sourcesJson = html.match(/sources\s*:\s*(\[[\s\S]*?\])/);
    if (sourcesJson) {
      try {
        const arr = JSON.parse(sourcesJson[1].replace(/,\s*]/g, ']')) as Array<{
          file?: string;
          label?: string;
          type?: string;
        }>;
        for (const item of arr) {
          if (!item.file || seen.has(item.file)) continue;
          seen.add(item.file);
          const isHls = item.file.includes('.m3u8') || item.type === 'hls';
          sources.push({
            url: item.file,
            type: isHls ? 'hls' : 'mp4',
            quality: (item.label ?? 'default').replace(/\s+/g, ''),
          });
        }
      } catch {
        /* abaikan JSON rusak */
      }
    }

    // Pola 2: {file: "...", label: "..."} / file:"..."
    const fileRe = /\{?\s*file\s*:\s*"(https?:[^"]+|\/\/[^"]+)"(?:\s*,\s*label\s*:\s*"([^"]*)")?/g;
    let m: RegExpExecArray | null;
    while ((m = fileRe.exec(html)) !== null) {
      let url = m[1];
      if (url.startsWith('//')) url = `https:${url}`;
      if (seen.has(url)) continue;
      if (/\.(vtt|srt)(\?|#|$)/i.test(url)) continue; // track subtitle — ditangani di bawah
      seen.add(url);
      sources.push({
        url,
        type: url.includes('.m3u8') ? 'hls' : 'mp4',
        quality: (m[2] ?? 'default').replace(/\s+/g, '') || 'default',
      });
    }

    // Pola 3: URL m3u8/mp4 mentah di dalam script
    const rawRe = /https?:[^\s"'\\]+\.m3u8[^\s"'\\]*/g;
    const rawMp4 = /https?:[^\s"'\\]+\.mp4[^\s"'\\]*/g;
    for (const re of [rawRe, rawMp4]) {
      let mm: RegExpExecArray | null;
      while ((mm = re.exec(html)) !== null) {
        const url = mm[0].replace(/\\u0026/g, '&').replace(/\\/g, '');
        if (seen.has(url)) continue;
        seen.add(url);
        sources.push({
          url,
          type: url.includes('.m3u8') ? 'hls' : 'mp4',
          quality: url.includes('.m3u8') ? 'auto' : 'default',
        });
      }
    }
    void pageUrl;

    // Subtitle tracks: {file:"...vtt", label:"...", kind:"captions"}
    const trackRe = /\{\s*file\s*:\s*"([^"]+\.(?:vtt|srt)[^"]*)"(?:[^}]*?label\s*:\s*"([^"]*)")?/gi;
    let t: RegExpExecArray | null;
    while ((t = trackRe.exec(html)) !== null) {
      let url = t[1];
      if (url.startsWith('//')) url = `https:${url}`;
      subtitles.push({ url, lang: (t[2] ?? 'en').trim() || 'en', label: t[2] });
    }
  }

  // ── DOWNLOAD ────────────────────────────────────────────
  async fetchDownloadLinks(episodeId: string): Promise<DownloadGroup[]> {
    const epSlug = slugFromUrl(decodeURIComponent(episodeId).trim());
    return this.cache.wrap(this.key('download', epSlug), async () => {
      const { html } = await this.fetchFromMirrors(
        appConfig.gogoBaseUrls,
        (b) => `${b}/${epSlug}`,
        (b) => this.headers(`${b}/`),
        (h) => h.includes('cf-download') || h.includes('load_anime'),
      );
      const groups = this.parseDownloadBlock(cheerio.load(html));
      if (groups.length === 0) {
        throw ApiError.notFound(`Link unduhan untuk "${epSlug}" tidak ditemukan`);
      }
      return groups;
    });
  }

  /** Parse div.cf-download di halaman episode Gogo. */
  private parseDownloadBlock($: cheerio.CheerioAPI): DownloadGroup[] {
    const byRes = new Map<string, DownloadLink[]>();
    $('div.cf-download a, .cf-download a, .download-anime a').each((_, el) => {
      const href = ($(el).attr('href') ?? '').trim();
      if (!href || !/^https?:\/\//i.test(href)) return;
      const label = $(el).text().trim();
      const resMatch = (href + ' ' + label).match(/(\d{3,4})\s*[pP]/);
      const resolution = resMatch ? `${resMatch[1]}p` : this.inferRes(label) ?? 'default';
      const server = this.serverName(this.hostOf(href), label);
      if (!byRes.has(resolution)) byRes.set(resolution, []);
      byRes.get(resolution)!.push({ server, url: href });
    });
    return sortGroupsByResolution(
      [...byRes.entries()].map(([resolution, links]) => ({ resolution, links })),
    );
  }

  private inferRes(label: string): string | undefined {
    const l = label.toLowerCase();
    if (l.includes('1080')) return '1080p';
    if (l.includes('720')) return '720p';
    if (l.includes('480')) return '480p';
    if (l.includes('360')) return '360p';
    return undefined;
  }

  private hostOf(url: string): string {
    try {
      return new URL(url).hostname.toLowerCase();
    } catch {
      return '';
    }
  }

  private serverName(host: string, fallbackLabel = ''): string {
    const h = host.toLowerCase();
    if (h.includes('mega')) return 'Mega';
    if (h.includes('drive.google') || h.includes('gdrive')) return 'Google Drive';
    if (h.includes('mp4upload')) return 'Mp4Upload';
    if (h.includes('dood')) return 'DoodStream';
    if (h.includes('streamwish') || h.includes('wish')) return 'StreamWish';
    if (h.includes('filemoon')) return 'Filemoon';
    if (h.includes('vidstream') || h.includes('gogo')) return 'Vidstream';
    if (h.includes('zippy') || h.includes('zippyshare')) return 'ZippyShare';
    if (h.includes('mirrored')) return 'Mirrored';
    if (h.includes('sendvid')) return 'Sendvid';
    if (h) return host.split('.')[0].replace(/^\w/, (c) => c.toUpperCase());
    return fallbackLabel.slice(0, 24) || 'Default';
  }
}
