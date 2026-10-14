/**
 * Projectnext shared types — modular ala Consumet.
 * Semua provider mengembalikan bentuk data yang sama agar gampang
 * ditukar/ditambah (Gogoanime, Samehadaku, dst).
 */

/** Hasil pencarian generik */
export interface AnimeSearchResult {
  /** slug/id unik di provider sumber, cth: "naruto" atau "one-piece" */
  id: string;
  title: string;
  /** URL absolut ke halaman detail di situs sumber */
  url: string;
  /** Poster — usahakan kualitas tertinggi yang tersedia di HTML sumber */
  image: string;
  /** Tahun rilis / "Released: 2019" bila ada */
  releaseDate?: string;
  /** Tipe: TV / Movie / OVA / ONA / Special / unknown */
  type?: string;
  /** khusus Samehadaku: skor, genre ringkas, dst */
  score?: string;
  genres?: string[];
  description?: string;
}

/** Satu episode dalam daftar info anime */
export interface AnimeEpisode {
  /** id episode untuk endpoint watch/download, cth gogo: "naruto-episode-10" */
  id: string;
  number: number;
  title?: string;
  url: string;
  /** khusus Samehadaku */
  date?: string;
}

/** Detail lengkap satu anime */
export interface AnimeInfo {
  id: string;
  title: string;
  url: string;
  /** Poster HD */
  image: string;
  description?: string;
  genres?: string[];
  status?: string;
  type?: string;
  releaseDate?: string;
  totalEpisodes: number;
  otherNames?: string[];
  trailer?: string;
  score?: string;
  studios?: string[];
  episodes: AnimeEpisode[];
  /** Batch link (Samehadaku) bila tersedia */
  batchUrl?: string | null;
}

/** Satu stream source (.m3u8 / mp4) */
export interface StreamSource {
  url: string;
  /** "hls" | "mp4" | "embed" */
  type: 'hls' | 'mp4' | 'embed';
  /** "1080p" / "720p" / "default" / "auto" */
  quality: string;
  /** true bila ini server embed yg belum ter-resolve (butuh buka di iframe/proxy) */
  isEmbed?: boolean;
  /** nama server embed: vidstream | mp4upload | streamwish | doodstream | blogger ... */
  server?: string;
}

/** Subtitle track */
export interface Subtitle {
  url: string;
  lang: string;
  label?: string;
}

/** Hasil endpoint watch */
export interface WatchData {
  episodeId: string;
  title?: string;
  /** iframe/embed utama bila ada */
  embedUrl?: string;
  headers?: Record<string, string>;
  sources: StreamSource[];
  subtitles: Subtitle[];
  /** server alternatif (Samehadaku: Blogger/Filedon/dll; Gogo: vidstream/dll) */
  servers?: { name: string; url: string }[];
  download?: DownloadGroup[];
}

/** Satu file unduhan */
export interface DownloadLink {
  server: string;
  url: string;
}

/** Grup unduhan per resolusi+format, cth { format: "MP4", resolution: "720p", links: [...] } */
export interface DownloadGroup {
  format?: string;
  resolution: string;
  links: DownloadLink[];
}

/** Info provider untuk GET /api/providers */
export interface ProviderMeta {
  id: string;
  name: string;
  baseUrl: string;
  languages: string[];
  supports: ('search' | 'info' | 'watch' | 'download')[];
}
