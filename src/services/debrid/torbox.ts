import { httpClient } from '../httpClient';
import { appConfig } from '../../config';
import { ApiError } from '../../middlewares/errorHandler';
import type { DebridFile, DebridResolver, UnrestrictResult } from './types';

const API = 'https://api.torbox.app/v1';

interface TorBoxEnvelope<T> {
  success?: boolean;
  detail?: string;
  error?: string;
  data?: T;
}

interface TorBoxTorrent {
  id: number;
  hash?: string;
  download_state?: string;
  download_finished?: boolean;
  progress?: number;
  files?: { id: number; name: string; size: number }[];
}

const VIDEO_EXT = ['.mp4', '.mkv', '.webm', '.avi', '.mov'];

function extractHash(magnet: string): string {
  const m = magnet.match(/btih:([a-fA-F0-9]{40}|[a-zA-Z2-7]{32})/);
  if (!m) throw ApiError.badRequest('Magnet tidak valid (btih tidak ditemukan)');
  return m[1].toLowerCase();
}

/** Pilih file video terbesar — MP4 diprioritaskan (playable di browser). */
function pickVideo(files: { id: number; name: string; size: number }[] | undefined): DebridFile | undefined {
  const videos = (files ?? []).filter((f) => VIDEO_EXT.some((e) => f.name.toLowerCase().endsWith(e)));
  if (videos.length === 0) return undefined;
  const mp4 = videos.filter((f) => f.name.toLowerCase().endsWith('.mp4'));
  const pool = mp4.length > 0 ? mp4 : videos;
  return pool.sort((a, b) => b.size - a.size)[0];
}

/**
 * Resolver TorBox (gratis). Alur:
 *  checkcached → createtorrent → mylist (poll) → requestdl (link CDN 3 jam)
 */
export class TorBoxResolver implements DebridResolver {
  readonly name = 'torbox';

  isConfigured(): boolean {
    return appConfig.torboxApiKey.length > 0;
  }

  private auth(): Record<string, string> {
    if (!this.isConfigured()) {
      throw ApiError.badRequest(
        'Debrid belum dikonfigurasi. Buat akun GRATIS di torbox.app, ambil API key, lalu set env TORBOX_API_KEY.',
      );
    }
    return { Authorization: `Bearer ${appConfig.torboxApiKey}` };
  }

  private failMessage(detail: unknown): string {
    const d = String(detail ?? '');
    if (/DOWNLOAD_TOO_LARGE/i.test(d)) return 'File >10GB — melebihi batas paket GRATIS TorBox.';
    if (/MONTHLY_LIMIT|month/i.test(d)) return 'Kuota bulanan TorBox habis (gratis: 10 unduhan/bulan).';
    if (/cooldown|24 hours|1 download/i.test(d)) return 'Batas TorBox gratis: 1 unduhan per 24 jam.';
    if (/ACTIVE_LIMIT|active/i.test(d)) return 'Slot aktif TorBox penuh (gratis: 1). Hapus antrean di dashboard torbox.app.';
    return d || 'TorBox menolak permintaan';
  }

  private async api<T>(method: 'GET' | 'POST', path: string, params?: Record<string, string>): Promise<T> {
    const url = `${API}${path}`;
    try {
      if (method === 'GET') {
        const qs = params ? `?${new URLSearchParams(params).toString()}` : '';
        const json = await httpClient.getJson<TorBoxEnvelope<T>>(`${url}${qs}`, this.auth());
        if (json.success === false) throw new Error(json.detail ?? json.error ?? 'TorBox error');
        return json.data as T;
      }
      const json = await httpClient.postFormJson<TorBoxEnvelope<T>>(url, params ?? {}, this.auth());
      if (json.success === false) throw new Error(json.detail ?? json.error ?? 'TorBox error');
      return json.data as T;
    } catch (e) {
      if (e instanceof ApiError) throw e;
      throw ApiError.upstream(`TorBox: ${this.failMessage((e as Error).message)}`);
    }
  }

  private async toResult(t: TorBoxTorrent): Promise<UnrestrictResult> {
    const finished = t.download_finished || t.download_state === 'cached';
    const file = pickVideo(t.files);
    if (finished && file) {
      const streamUrl = await this.api<string>('GET', '/api/torrents/requestdl', {
        token: appConfig.torboxApiKey,
        torrent_id: String(t.id),
        file_id: String(file.id),
      });
      return { state: 'ready', torrentId: t.id, streamUrl, file, progress: 1 };
    }
    if (!file && finished) {
      return { state: 'pending', torrentId: t.id, note: 'Torrent siap tapi tidak ada file video di dalamnya.' };
    }
    return {
      state: t.progress && t.progress > 0 ? 'downloading' : 'pending',
      torrentId: t.id,
      file,
      progress: t.progress ?? 0,
      note: 'TorBox sedang mengunduh (paket gratis antre 1 slot). Poll endpoint ini berkala.',
    };
  }

  async unrestrict(magnet: string): Promise<UnrestrictResult> {
    this.auth();
    const hash = extractHash(magnet.trim());
    // 1) Entri lama dengan hash sama? pakai ulang (hemat kuota!).
    try {
      const mine = await this.api<TorBoxTorrent[]>('GET', '/api/torrents/mylist', { bypass_cache: 'true' });
      const existing = (mine ?? []).find((t) => (t.hash ?? '').toLowerCase() === hash);
      if (existing) return this.toResult(existing);
    } catch {
      /* lanjut buat baru */
    }
    // 2) Buat entri baru (cached = instan, tidak makan slot/kuota harian).
    const created = await this.api<{ torrent_id: number }>('POST', '/api/torrents/createtorrent', {
      magnet,
      seed: '1',
    });
    // 3) Ambil status awal.
    const fresh = await this.api<TorBoxTorrent>('GET', '/api/torrents/mylist', {
      id: String(created.torrent_id),
    });
    const one = Array.isArray(fresh) ? fresh[0] : (fresh as unknown as TorBoxTorrent);
    return this.toResult(one);
  }

  async poll(torrentId: number): Promise<UnrestrictResult> {
    this.auth();
    if (!Number.isFinite(torrentId)) throw ApiError.badRequest('torrentId tidak valid');
    const fresh = await this.api<TorBoxTorrent>('GET', '/api/torrents/mylist', { id: String(torrentId) });
    const one = Array.isArray(fresh) ? fresh[0] : (fresh as unknown as TorBoxTorrent);
    if (!one) throw ApiError.notFound('Torrent tidak ditemukan di akun TorBox');
    return this.toResult(one);
  }
}
