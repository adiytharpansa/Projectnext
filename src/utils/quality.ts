import type { DownloadGroup } from '../types';

/** Peringkat resolusi — tertinggi dulu; tak dikenal ('default' dll) terbawah. */
const RANK = ['2160p', '1080p', '720p', '540p', '480p', '360p'];

export function resolutionRank(resolution: string): number {
  const i = RANK.indexOf(resolution.toLowerCase());
  return i === -1 ? RANK.length : i;
}

/** Sort grup unduhan: resolusi tertinggi → terendah. */
export function sortGroupsByResolution(groups: DownloadGroup[]): DownloadGroup[] {
  return [...groups].sort((a, b) => resolutionRank(a.resolution) - resolutionRank(b.resolution));
}
