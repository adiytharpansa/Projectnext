import type { Request, Response } from 'express';
import { httpClient } from '../services/httpClient';
import { ApiError, asyncHandler } from '../middlewares/errorHandler';
import { isAllowedProxyUrl, resolveM3u8Url } from '../utils/url';

const PICK_HEADERS = ['referer', 'referrer', 'origin', 'user-agent', 'cookie'] as const;

function forwardHeaders(req: Request): Record<string, string> {
  const out: Record<string, string> = {};
  for (const h of PICK_HEADERS) {
    const v = req.query[h] ?? req.headers[h];
    if (typeof v === 'string' && v) {
      out[h === 'referrer' ? 'Referer' : h] = v;
    }
  }
  return out;
}

function targetUrl(req: Request): string {
  const raw = String(req.query.url ?? '');
  if (!raw) throw ApiError.badRequest('Parameter "url" wajib diisi');
  if (!isAllowedProxyUrl(raw)) throw ApiError.badRequest('URL tidak valid / tidak diizinkan');
  return raw;
}

/**
 * GET /api/proxy?url=&referer=&origin=
 * Proxy generik (image, subtitle, segmen .ts, file mp4) untuk bypass
 * CORS + Referer/User-Agent situs sumber.
 */
export const proxyFetch = asyncHandler(async (req: Request, res: Response) => {
  const url = targetUrl(req);
  const headers = forwardHeaders(req);
  try {
    const upstream = await httpClient.fetchStream(url, headers);
    const ct = upstream.headers['content-type'];
    if (ct) res.setHeader('Content-Type', String(ct));
    const cl = upstream.headers['content-length'];
    if (cl) res.setHeader('Content-Length', String(cl));
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    (upstream.data as NodeJS.ReadableStream).pipe(res);
  } catch (e) {
    throw ApiError.upstream(`Proxy gagal mengambil URL: ${(e as Error).message}`);
  }
});

/**
 * GET /api/proxy/m3u8?url=&referer=
 * Proxy playlist HLS + rewrite semua URI segmen/playlist anak ke endpoint
 * proxy ini, sehingga player cukup memutar satu URL tanpa kena CORS/Referer.
 */
export const proxyM3u8 = asyncHandler(async (req: Request, res: Response) => {
  const url = targetUrl(req);
  const headers = forwardHeaders(req);
  let text: string;
  try {
    text = await httpClient.getText(url, headers);
  } catch (e) {
    throw ApiError.upstream(`Proxy m3u8 gagal: ${(e as Error).message}`);
  }

  const proto = req.protocol;
  const host = req.get('host');
  const basePath = '/api/proxy/m3u8';
  const refererParam = headers['Referer'] ? `&referer=${encodeURIComponent(headers['Referer'])}` : '';

  const rewritten = text
    .split('\n')
    .map((line) => {
      const t = line.trim();
      if (!t || t.startsWith('#')) {
        // Rewrite URI di dalam tag EXT-X-KEY / EXT-X-MAP juga
        if (t.startsWith('#EXT-X-KEY') || t.startsWith('#EXT-X-MAP')) {
          return line.replace(/URI="([^"]+)"/, (_m, uri: string) => {
            const abs = resolveM3u8Url(url, uri);
            return `URI="${proto}://${host}${basePath}?url=${encodeURIComponent(abs)}${refererParam}"`;
          });
        }
        return line;
      }
      const abs = resolveM3u8Url(url, t);
      return `${proto}://${host}${basePath}?url=${encodeURIComponent(abs)}${refererParam}`;
    })
    .join('\n');

  res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.send(rewritten);
});
