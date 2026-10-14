import type { Request, Response } from 'express';
import { getProvider, listProviders } from '../providers';
import { ApiError, asyncHandler } from '../middlewares/errorHandler';

const ok = (res: Response, data: unknown) =>
  res.json({ success: true, status: 200, data });

/** GET /api/providers */
export const getProviders = asyncHandler(async (_req: Request, res: Response) => {
  ok(res, listProviders().map((p) => p.meta));
});

/** GET /api/anime/:provider/search?query= */
export const searchAnime = asyncHandler(async (req: Request, res: Response) => {
  const query = String(req.query.query ?? req.query.q ?? '');
  if (!query.trim()) throw ApiError.badRequest('Parameter "query" wajib diisi. Contoh: ?query=naruto');
  const provider = getProvider(req.params.provider);
  const results = await provider.search(query);
  ok(res, { provider: provider.id, query, count: results.length, results });
});

/** GET /api/anime/:provider/info/:id */
export const getAnimeInfo = asyncHandler(async (req: Request, res: Response) => {
  const provider = getProvider(req.params.provider);
  const data = await provider.fetchInfo(req.params.id);
  ok(res, { provider: provider.id, ...data });
});

/** GET /api/anime/:provider/watch/:episodeId */
export const getWatchSources = asyncHandler(async (req: Request, res: Response) => {
  const provider = getProvider(req.params.provider);
  const data = await provider.fetchSources(req.params.episodeId);
  ok(res, { provider: provider.id, ...data });
});

/** GET /api/anime/:provider/download/:episodeId */
export const getDownloadLinks = asyncHandler(async (req: Request, res: Response) => {
  const provider = getProvider(req.params.provider);
  const groups = await provider.fetchDownloadLinks(req.params.episodeId);
  ok(res, { provider: provider.id, episodeId: req.params.episodeId, count: groups.length, groups });
});

// ── v1 (query-param style, untuk klien my-anime) ──────────

function v1Provider(req: Request): ReturnType<typeof getProvider> | undefined {
  const p = String(req.query.provider ?? '').trim().toLowerCase();
  return p ? getProvider(p) : undefined;
}

/** GET /api/v1/anime/search?query=&provider= (provider opsional → agregat semua) */
export const v1SearchAnime = asyncHandler(async (req: Request, res: Response) => {
  const query = String(req.query.query ?? req.query.q ?? '');
  if (!query.trim()) throw ApiError.badRequest('Parameter "query" wajib diisi. Contoh: ?query=naruto');
  const single = v1Provider(req);
  const targets = single ? [single] : listProviders();
  const settled = await Promise.allSettled(
    targets.map(async (provider) => {
      const results = await provider.search(query);
      return results.map((r) => ({ provider: provider.id, ...r }));
    }),
  );
  const results = settled.flatMap((s) => (s.status === 'fulfilled' ? s.value : []));
  const errors = settled
    .map((s, i) => ({ s, i }))
    .filter(({ s }) => s.status === 'rejected')
    .map(({ s, i }) => ({
      provider: targets[i].id,
      message: (s as PromiseRejectedResult).reason?.message ?? String((s as PromiseRejectedResult).reason),
    }));
  ok(res, { query, count: results.length, results, ...(errors.length ? { errors } : {}) });
});

/** GET /api/v1/anime/info?provider=&id= */
export const v1AnimeInfo = asyncHandler(async (req: Request, res: Response) => {
  const id = String(req.query.id ?? '');
  if (!id.trim()) throw ApiError.badRequest('Parameter "id" wajib diisi');
  const provider = v1Provider(req) ?? getProvider('gogo');
  const data = await provider.fetchInfo(id);
  ok(res, { provider: provider.id, ...data });
});

/** GET /api/v1/anime/watch?provider=&episodeId= */
export const v1WatchSources = asyncHandler(async (req: Request, res: Response) => {
  const episodeId = String(req.query.episodeId ?? req.query.episode ?? '');
  if (!episodeId.trim()) throw ApiError.badRequest('Parameter "episodeId" wajib diisi');
  const provider = v1Provider(req) ?? getProvider('gogo');
  const data = await provider.fetchSources(episodeId);
  ok(res, { provider: provider.id, ...data });
});

/** GET /api/v1/anime/download?provider=&episodeId= */
export const v1DownloadLinks = asyncHandler(async (req: Request, res: Response) => {
  const episodeId = String(req.query.episodeId ?? req.query.episode ?? '');
  if (!episodeId.trim()) throw ApiError.badRequest('Parameter "episodeId" wajib diisi');
  const provider = v1Provider(req) ?? getProvider('gogo');
  const groups = await provider.fetchDownloadLinks(episodeId);
  ok(res, { provider: provider.id, episodeId, count: groups.length, groups });
});
