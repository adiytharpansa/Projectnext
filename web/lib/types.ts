/** Tipe data klien my-anime — cerminan kontrak backend Projectnext. */

export interface AnimeSearchResult {
  provider: string;
  id: string;
  title: string;
  url: string;
  image: string;
  releaseDate?: string;
  type?: string;
  score?: string;
  genres?: string[];
  description?: string;
}

export interface AnimeEpisode {
  id: string;
  number: number;
  title?: string;
  url: string;
  date?: string;
}

export interface AnimeInfo {
  provider: string;
  id: string;
  title: string;
  url: string;
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
  episodes: AnimeEpisode[];
  batchUrl?: string | null;
}

export interface StreamSource {
  url: string;
  type: 'hls' | 'mp4' | 'embed';
  quality: string;
  isEmbed?: boolean;
  server?: string;
}

/**
 * Tipe player-facing. Alias disiplin dari model backend `StreamSource`
 * agar komponen memakai satu nama kanonis: VideoSource.
 */
export type VideoSource = StreamSource;
export type VideoSourceType = VideoSource['type'];

export interface Subtitle {
  url: string;
  lang: string;
  label?: string;
}

/** Alias kanonis untuk track subtitle di player. */
export type SubtitleTrack = Subtitle;

export interface DownloadLink {
  server: string;
  url: string;
}

export interface DownloadGroup {
  format?: string;
  resolution: string;
  links: DownloadLink[];
}

export interface WatchData {
  provider: string;
  episodeId: string;
  title?: string;
  embedUrl?: string;
  headers?: Record<string, string>;
  sources: StreamSource[];
  subtitles: Subtitle[];
  servers?: { name: string; url: string }[];
  download?: DownloadGroup[];
}

export interface ProviderMeta {
  id: string;
  name: string;
  baseUrl: string;
  languages: string[];
  supports: string[];
}
