import type {
  AnimeInfo,
  AnimeSearchResult,
  DownloadGroup,
  ProviderMeta,
  WatchData,
} from '../types';
import { MemoryCache } from '../utils/cache';
import { appConfig } from '../config';
import { httpClient } from '../services/httpClient';
import { ApiError } from '../middlewares/errorHandler';

/**
 * BaseProvider abstrak — kontrak OOP ala Consumet.
 *
 * Untuk menambah provider baru:
 *  1. Buat class `XyzProvider extends BaseProvider`
 *  2. Implementasikan search/fetchInfo/fetchSources/fetchDownloadLinks
 *  3. Daftarkan di `src/providers/index.ts`
 *  4. Route/controller otomatis mengekspos endpoint baru tanpa diubah.
 */
export abstract class BaseProvider {
  /** id unik lowercase, dipakai di path: /api/anime/:provider/... */
  abstract readonly id: string;
  abstract readonly name: string;
  abstract readonly baseUrl: string;
  abstract readonly languages: string[];

  protected cache = new MemoryCache(appConfig.cacheTtlSeconds);

  abstract search(query: string): Promise<AnimeSearchResult[]>;
  abstract fetchInfo(id: string): Promise<AnimeInfo>;
  abstract fetchSources(episodeId: string): Promise<WatchData>;
  abstract fetchDownloadLinks(episodeId: string): Promise<DownloadGroup[]>;

  get meta(): ProviderMeta {
    return {
      id: this.id,
      name: this.name,
      baseUrl: this.baseUrl,
      languages: this.languages,
      supports: ['search', 'info', 'watch', 'download'],
    };
  }

  /** Key cache namespaced per provider. */
  protected key(...parts: string[]): string {
    return [this.id, ...parts].join(':');
  }

  /**
   * Fetch HTML dari daftar mirror berurutan. Mirror yang melempar error
   * ATAU lolos validasi (halaman parkir / JS-challenge / dibajak) dilewati.
   * Mengembalikan HTML + base yang berhasil agar URL absolut konsisten.
   */
  protected async fetchFromMirrors(
    bases: string[],
    buildUrl: (base: string) => string,
    buildHeaders: (base: string) => Record<string, string>,
    validate?: (html: string) => boolean,
  ): Promise<{ base: string; html: string }> {
    let lastErr: unknown = new Error('tidak ada mirror dikonfigurasi');
    for (const base of bases) {
      try {
        const html = await httpClient.getText(buildUrl(base), buildHeaders(base));
        if (validate && !validate(html)) {
          lastErr = new Error(`respons tak dikenal dari ${base} (parkir/challenge/tema berubah?)`);
          continue;
        }
        return { base, html };
      } catch (e) {
        lastErr = e;
      }
    }
    throw ApiError.upstream(
      `[${this.name}] Semua mirror gagal (${bases.join(', ')}). ` +
        `Set mirror aktif via env. Penyebab terakhir: ${(lastErr as Error)?.message ?? lastErr}`,
    );
  }
}
