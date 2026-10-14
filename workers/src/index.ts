import './shim'; // WAJIB PALING AWAL — patch Request/fetch sebelum axios dimuat
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { getProvider, listProviders } from '../../src/providers';
import { ApiError } from '../../src/middlewares/errorHandler';
import { TorBoxResolver } from '../../src/services/debrid/torbox';
import { isAllowedProxyUrl, resolveM3u8Url } from '../../src/utils/url';
import { applyEnv, type WorkerEnv } from './env';

/**
 * Projectnext API di Cloudflare Workers (Hono).
 * Reuse penuh: provider OOP, TorBox resolver, URL utils dari backend Express.
 * Yang ditulis ulang khusus Workers: routing, envelope error, proxy (fetch
 * streaming), rate-limit (in-memory per-isolate, best-effort).
 *
 * Batasan jujur: IP egress Workers sering diblokir anti-bot situs sumber
 * HTML; endpoint siap-pakai terbaik di sini: torrentio/nyaa/crunchyroll/
 * iqiyi/kitsu + debrid. Untuk Gogo/Samehadaku berat, pakai backend Express
 * di Render/VPS.
 */

type Env = { Bindings: WorkerEnv };

const app = new Hono<Env>();
const torbox = new TorBoxResolver();

// ── Middleware umum ──
app.use('*', async (c, next) => {
  applyEnv(c.env);
  await next();
});
app.use('/api/*', cors({ origin: '*' }));

// Rate-limit sederhana per isolate (best-effort; untuk ketat pakai Rate Limit Rules CF)
const hits = new Map<string, { n: number; reset: number }>();
app.use('/api/*', async (c, next) => {
  const max = Number(c.env.RATE_LIMIT_MAX ?? 120);
  const ip = c.req.header('cf-connecting-ip') ?? 'anon';
  const now = Date.now();
  const e = hits.get(ip);
  if (!e || now > e.reset) {
    hits.set(ip, { n: 1, reset: now + 60_000 });
  } else if (e.n >= max) {
    return fail(c, 429, 'Terlalu banyak request, coba lagi nanti');
  } else {
    e.n += 1;
  }
  await next();
});

// ── Helpers envelope ──
function ok(c: { json: (o: unknown) => Response }, data: unknown): Response {
  return c.json({ success: true, status: 200, data });
}

function fail(c: { json: (o: unknown, s?: number) => Response }, status: number, message: string): Response {
  return c.json({ success: false, status, message }, status as 400);
}

function errOf(e: unknown): { status: number; message: string } {
  if (e instanceof ApiError) return { status: e.status, message: e.message };
  return { status: 500, message: e instanceof Error ? e.message : 'Internal server error' };
}

async function guard(c: { json: (o: unknown, s?: number) => Response }, fn: () => Promise<Response>): Promise<Response> {
  try {
    return await fn();
  } catch (e) {
    const { status, message } = errOf(e);
    if (status === 500) console.error('[projectnext-workers]', e);
    return fail(c, status, message);
  }
}

// ── Landing & health ──
app.get('/', (c) =>
  ok(c, {
    name: 'Projectnext (Workers)',
    description: 'Modular anime scraper API — Hono edition untuk Cloudflare Workers',
    docs: {
      providers: 'GET /api/providers',
      v1Search: 'GET /api/v1/anime/search?query=naruto&provider=gogo',
      v1Info: 'GET /api/v1/anime/info?provider=gogo&id=naruto',
      v1Watch: 'GET /api/v1/anime/watch?provider=gogo&episodeId=naruto-episode-10',
      v1Download: 'GET /api/v1/anime/download?provider=gogo&episodeId=...',
      debridStatus: 'GET /api/v1/debrid/status',
      debridUnrestrict: 'POST /api/v1/debrid/unrestrict { magnet }',
      debridPoll: 'GET /api/v1/debrid/torrent/:id',
      proxy: 'GET /api/proxy?url=<encoded>&referer=<encoded>',
      proxyM3u8: 'GET /api/proxy/m3u8?url=<encoded>&referer=<encoded>',
      health: 'GET /api/health',
    },
  }),
);

app.get('/api/health', (c) => ok(c, { status: 200, runtime: 'cloudflare-workers' }));
app.get('/api/providers', (c) => ok(c, listProviders().map((p) => p.meta)));
app.get('/api/v1/providers', (c) => ok(c, listProviders().map((p) => p.meta)));

// ── v1 (query-param) ──
app.get('/api/v1/anime/search', (c) =>
  guard(c, async () => {
    const query = c.req.query('query') ?? c.req.query('q') ?? '';
    if (!query.trim()) throw ApiError.badRequest('Parameter "query" wajib diisi');
    const pv = (c.req.query('provider') ?? '').trim().toLowerCase();
    const targets = pv ? [getProvider(pv)] : listProviders();
    const settled = await Promise.allSettled(
      targets.map(async (p) => (await p.search(query)).map((r) => ({ provider: p.id, ...r }))),
    );
    const results = settled.flatMap((s) => (s.status === 'fulfilled' ? s.value : []));
    const errors = settled
      .map((s, i) => ({ s, i }))
      .filter(({ s }) => s.status === 'rejected')
      .map(({ s, i }) => ({
        provider: targets[i].id,
        message:
          (s as PromiseRejectedResult).reason?.message ?? String((s as PromiseRejectedResult).reason),
      }));
    return ok(c, { query, count: results.length, results, ...(errors.length ? { errors } : {}) });
  }),
);

app.get('/api/v1/anime/info', (c) =>
  guard(c, async () => {
    const id = c.req.query('id') ?? '';
    if (!id.trim()) throw ApiError.badRequest('Parameter "id" wajib diisi');
    const pv = (c.req.query('provider') ?? '').trim().toLowerCase();
    const p = pv ? getProvider(pv) : getProvider('gogo');
    return ok(c, { provider: p.id, ...(await p.fetchInfo(id)) });
  }),
);

app.get('/api/v1/anime/watch', (c) =>
  guard(c, async () => {
    const episodeId = c.req.query('episodeId') ?? c.req.query('episode') ?? '';
    if (!episodeId.trim()) throw ApiError.badRequest('Parameter "episodeId" wajib diisi');
    const pv = (c.req.query('provider') ?? '').trim().toLowerCase();
    const p = pv ? getProvider(pv) : getProvider('gogo');
    return ok(c, { provider: p.id, ...(await p.fetchSources(episodeId)) });
  }),
);

app.get('/api/v1/anime/download', (c) =>
  guard(c, async () => {
    const episodeId = c.req.query('episodeId') ?? c.req.query('episode') ?? '';
    if (!episodeId.trim()) throw ApiError.badRequest('Parameter "episodeId" wajib diisi');
    const pv = (c.req.query('provider') ?? '').trim().toLowerCase();
    const p = pv ? getProvider(pv) : getProvider('gogo');
    const groups = await p.fetchDownloadLinks(episodeId);
    return ok(c, { provider: p.id, episodeId, count: groups.length, groups });
  }),
);

// ── Legacy path-param (kompatibel backend Express) ──
app.get('/api/anime/:provider/search', (c) =>
  guard(c, async () => {
    const query = c.req.query('query') ?? c.req.query('q') ?? '';
    if (!query.trim()) throw ApiError.badRequest('Parameter "query" wajib diisi');
    const p = getProvider(c.req.param('provider'));
    const results = await p.search(query);
    return ok(c, { provider: p.id, query, count: results.length, results });
  }),
);

app.get('/api/anime/:provider/info/:id', (c) =>
  guard(c, async () => {
    const p = getProvider(c.req.param('provider'));
    return ok(c, { provider: p.id, ...(await p.fetchInfo(c.req.param('id'))) });
  }),
);

app.get('/api/anime/:provider/watch/:episodeId', (c) =>
  guard(c, async () => {
    const p = getProvider(c.req.param('provider'));
    return ok(c, { provider: p.id, ...(await p.fetchSources(c.req.param('episodeId'))) });
  }),
);

app.get('/api/anime/:provider/download/:episodeId', (c) =>
  guard(c, async () => {
    const p = getProvider(c.req.param('provider'));
    const groups = await p.fetchDownloadLinks(c.req.param('episodeId'));
    return ok(c, { provider: p.id, episodeId: c.req.param('episodeId'), count: groups.length, groups });
  }),
);

// ── Debrid (TorBox) ──
app.get('/api/v1/debrid/status', (c) =>
  ok(c, {
    configured: torbox.isConfigured(),
    provider: torbox.name,
    plan: 'free',
    limits: {
      maxSize: '10GB per torrent',
      adds: '1 per 24 jam, maks 10 per bulan',
      slots: '1 aktif (file cached bebas slot)',
    },
    hint: torbox.isConfigured()
      ? 'Siap. POST /api/v1/debrid/unrestrict { magnet }'
      : 'Set secret TORBOX_API_KEY (npx wrangler secret put TORBOX_API_KEY)',
  }),
);

app.post('/api/v1/debrid/unrestrict', (c) =>
  guard(c, async () => {
    const body = (await c.req.json().catch(() => ({}))) as { magnet?: string };
    const magnet = String(body.magnet ?? '');
    if (!magnet.trim()) throw ApiError.badRequest('Body { magnet } wajib diisi');
    return ok(c, { provider: torbox.name, ...(await torbox.unrestrict(magnet)) });
  }),
);

app.get('/api/v1/debrid/torrent/:id', (c) =>
  guard(c, async () => ok(c, { provider: torbox.name, ...(await torbox.poll(Number(c.req.param('id')))) })),
);

// ── Proxy (fetch streaming + rewrite m3u8) ──
const PICK = ['referer', 'referrer', 'origin', 'user-agent', 'cookie'] as const;

function proxyTarget(url: URL): string {
  const raw = url.searchParams.get('url') ?? '';
  if (!raw) throw ApiError.badRequest('Parameter "url" wajib diisi');
  if (!isAllowedProxyUrl(raw)) throw ApiError.badRequest('URL tidak valid / tidak diizinkan');
  return raw;
}

function proxyHeaders(url: URL, req: Request): Record<string, string> {
  const out: Record<string, string> = {};
  for (const h of PICK) {
    const v = url.searchParams.get(h) ?? req.headers.get(h);
    if (v) out[h === 'referrer' ? 'Referer' : h] = v;
  }
  return out;
}

app.get('/api/proxy', (c) =>
  guard(c, async () => {
    const target = proxyTarget(new URL(c.req.url));
    const upstream = await fetch(target, { headers: proxyHeaders(new URL(c.req.url), c.req.raw) });
    if (!upstream.ok || !upstream.body) {
      throw ApiError.upstream(`Proxy gagal mengambil URL (HTTP ${upstream.status})`);
    }
    const headers = new Headers();
    const ct = upstream.headers.get('content-type');
    if (ct) headers.set('Content-Type', ct);
    headers.set('Access-Control-Allow-Origin', '*');
    headers.set('Cache-Control', 'public, max-age=3600');
    return new Response(upstream.body, { headers });
  }),
);

app.get('/api/proxy/m3u8', (c) =>
  guard(c, async () => {
    const pageUrl = new URL(c.req.url);
    const target = proxyTarget(pageUrl);
    const fwd = proxyHeaders(pageUrl, c.req.raw);
    const upstream = await fetch(target, { headers: fwd });
    if (!upstream.ok) throw ApiError.upstream(`Proxy m3u8 gagal (HTTP ${upstream.status})`);
    const text = await upstream.text();
    const refererParam = fwd['Referer'] ? `&referer=${encodeURIComponent(fwd['Referer'])}` : '';
    const base = `${pageUrl.protocol}//${pageUrl.host}/api/proxy/m3u8`;
    const rewritten = text
      .split('\n')
      .map((line) => {
        const t = line.trim();
        if (!t || t.startsWith('#')) {
          if (t.startsWith('#EXT-X-KEY') || t.startsWith('#EXT-X-MAP')) {
            return line.replace(/URI="([^"]+)"/, (_m, uri: string) => {
              const abs = resolveM3u8Url(target, uri);
              return `URI="${base}?url=${encodeURIComponent(abs)}${refererParam}"`;
            });
          }
          return line;
        }
        return `${base}?url=${encodeURIComponent(resolveM3u8Url(target, t))}${refererParam}`;
      })
      .join('\n');
    return new Response(rewritten, {
      headers: { 'Content-Type': 'application/vnd.apple.mpegurl', 'Access-Control-Allow-Origin': '*' },
    });
  }),
);

// ── 404 ──
app.notFound((c) => fail(c, 404, 'Route not found'));

export default app;
