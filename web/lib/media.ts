import type { DownloadGroup } from './types';

/** Urutan resolusi menaik — untuk sort tampilan (dibalik bila perlu). */
export const RESOLUTION_ORDER = ['360p', '480p', '540p', '720p', '1080p', '2160p'];

function orderIndex(resolution: string): number {
  // 'default' / tak dikenal = peringkat terbawah di kedua arah sort.
  return RESOLUTION_ORDER.indexOf(resolution.toLowerCase());
}

/** Sort grup unduhan dari resolusi tertinggi ke terendah. */
export function sortDownloadGroups(groups: DownloadGroup[]): DownloadGroup[] {
  return [...groups].sort((a, b) => orderIndex(b.resolution) - orderIndex(a.resolution));
}

/** "3661" detik → "1:01:01". Aman untuk NaN/Infinity. */
export function formatSeconds(total: number): string {
  if (!Number.isFinite(total) || total < 0) return '0:00';
  const s = Math.floor(total);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const mm = h > 0 ? String(m).padStart(2, '0') : String(m);
  return `${h > 0 ? `${h}:` : ''}${mm}:${String(sec).padStart(2, '0')}`;
}

/** Hostname aman untuk label (toleran URL rusak). */
export function safeHostname(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return 'tautan';
  }
}

/** Label kualitas level HLS dari height/bitrate. */
export function levelLabel(level: { height?: number; bitrate?: number }): string {
  if (level.height && level.height > 0) return `${level.height}p`;
  if (level.bitrate && level.bitrate > 0) return `${Math.round(level.bitrate / 1000)}k`;
  return 'SD';
}
