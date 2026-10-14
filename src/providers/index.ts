import type { BaseProvider } from './BaseProvider';
import { GogoanimeProvider } from './GogoanimeProvider';
import { SamehadakuProvider } from './SamehadakuProvider';
import { CrunchyrollProvider } from './CrunchyrollProvider';
import { NyaaProvider } from './NyaaProvider';
import { TorrentioProvider } from './TorrentioProvider';
import { GogoByProvider } from './GogoByProvider';
import { IqiyiProvider } from './IqiyiProvider';
import { ApiError } from '../middlewares/errorHandler';

export { BaseProvider } from './BaseProvider';
export { GogoanimeProvider } from './GogoanimeProvider';
export { SamehadakuProvider } from './SamehadakuProvider';
export { CrunchyrollProvider } from './CrunchyrollProvider';
export { NyaaProvider } from './NyaaProvider';
export { TorrentioProvider } from './TorrentioProvider';
export { GogoByProvider } from './GogoByProvider';
export { IqiyiProvider } from './IqiyiProvider';

/**
 * Registry provider. Tambah provider baru cukup append di sini —
 * route & controller otomatis mendukungnya via :provider param.
 *
 * Contoh:
 *   import { OtakudesuProvider } from './OtakudesuProvider';
 *   providers.set('otakudesu', new OtakudesuProvider());
 */
const gogo = new GogoanimeProvider();
const samehadaku = new SamehadakuProvider();
const crunchyroll = new CrunchyrollProvider();
const nyaa = new NyaaProvider();
const torrentio = new TorrentioProvider();
const gogoby = new GogoByProvider();
const iqiyi = new IqiyiProvider();

const providers = new Map<string, BaseProvider>([
  [gogo.id, gogo],
  ['gogoanime', gogo], // alias global (EN)
  ['anitaku', gogo], // alias
  [samehadaku.id, samehadaku],
  ['sd', samehadaku], // alias singkat
  [crunchyroll.id, crunchyroll], // metadata resmi (tanpa stream, DRM)
  ['cr', crunchyroll],
  [nyaa.id, nyaa], // unduhan torrent
  [torrentio.id, torrentio], // agregat torrent via Kitsu
  ['torrent', torrentio],
  [gogoby.id, gogoby], // klon Gogo tema WP — HLS langsung + subtitle
  ['gogoanimeby', gogoby],
  [iqiyi.id, iqiyi], // metadata iQIYI (tanpa stream, DRM+signed)
  ['iq', iqiyi],
]);

export function getProvider(id: string): BaseProvider {
  const key = decodeURIComponent(id).trim().toLowerCase();
  const p = providers.get(key);
  if (!p) {
    throw ApiError.notFound(
      `Provider "${id}" tidak dikenal. Tersedia: ${[...new Set([...providers.values()].map((v) => v.id))].join(', ')}`,
    );
  }
  return p;
}

export function listProviders(): BaseProvider[] {
  // dedup alias
  return [...new Map([...providers.values()].map((p) => [p.id, p])).values()];
}
