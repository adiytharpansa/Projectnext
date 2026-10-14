import type { Request, Response } from 'express';
import { TorBoxResolver } from '../services/debrid/torbox';
import { ApiError, asyncHandler } from '../middlewares/errorHandler';

const resolver = new TorBoxResolver();

const ok = (res: Response, data: unknown) => res.json({ success: true, status: 200, data });

/** GET /api/v1/debrid/status */
export const debridStatus = asyncHandler(async (_req: Request, res: Response) => {
  ok(res, {
    configured: resolver.isConfigured(),
    provider: resolver.name,
    plan: 'free',
    limits: {
      maxSize: '10GB per torrent',
      adds: '1 per 24 jam, maks 10 per bulan',
      slots: '1 aktif (file cached bebas slot)',
    },
    hint: resolver.isConfigured()
      ? 'Siap. POST /api/v1/debrid/unrestrict { magnet }'
      : 'Set env TORBOX_API_KEY (gratis di torbox.app → Settings)',
  });
});

/** POST /api/v1/debrid/unrestrict { magnet } */
export const debridUnrestrict = asyncHandler(async (req: Request, res: Response) => {
  const magnet = String(req.body?.magnet ?? '');
  if (!magnet.trim()) throw ApiError.badRequest('Body { magnet } wajib diisi');
  const result = await resolver.unrestrict(magnet);
  ok(res, { provider: resolver.name, ...result });
});

/** GET /api/v1/debrid/torrent/:id */
export const debridPoll = asyncHandler(async (req: Request, res: Response) => {
  const result = await resolver.poll(Number(req.params.id));
  ok(res, { provider: resolver.name, ...result });
});
