'use client';

import Link from 'next/link';
import { use, useCallback, useEffect, useState } from 'react';
import DownloadSection from '@/components/DownloadSection';
import DebridPanel from '@/components/DebridPanel';
import EpisodeList from '@/components/EpisodeList';
import { ErrorState, LoadingState } from '@/components/StateViews';
import VideoPlayer from '@/components/VideoPlayer';
import { ApiError, fetchAnimeInfo, fetchDownloadGroups, fetchWatchData } from '@/lib/api';
import type { AnimeInfo, DownloadGroup, WatchData } from '@/lib/types';
import { saveHistory } from '@/lib/watchlist';

export const runtime = 'edge';

export default function WatchPage({
  params,
}: {
  params: Promise<{ provider: string; episodeId: string }>;
}) {
  const { provider: rawProvider, episodeId: rawEpisodeId } = use(params);
  const provider = decodeURIComponent(rawProvider);
  const episodeId = decodeURIComponent(rawEpisodeId);
  const [watch, setWatch] = useState<WatchData | null>(null);
  const [downloads, setDownloads] = useState<DownloadGroup[] | null>(null);
  const [info, setInfo] = useState<AnimeInfo | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setWatch(null);
    setDownloads(null);
    setError(null);
    try {
      const w = await fetchWatchData(provider, episodeId);
      setWatch(w);
      // Download dari respons watch bila ada, kalau tidak fetch endpoint khusus
      const groups = w.download && w.download.length > 0
        ? w.download
        : (await fetchDownloadGroups(provider, episodeId).catch(() => null))?.groups ?? [];
      setDownloads(groups);
      // Info untuk judul + navigasi episode (best-effort, jangan gagalkan player)
      const animeId = episodeId.replace(/-episode-\d+.*$/i, '').replace(/-eps?-.*$/i, '');
      if (animeId && animeId !== episodeId) {
        fetchAnimeInfo(provider, animeId).then(setInfo).catch(() => {});
      }
      saveHistory({
        provider,
        animeId,
        episodeId,
        title: w.title ?? episodeId,
        image: '',
      }).catch(() => {});
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Gagal memuat stream');
    }
  }, [provider, episodeId]);

  useEffect(() => {
    load();
  }, [load]);

  if (error) return <div className="pt-6"><ErrorState message={error} retry={load} /></div>;
  if (!watch) return <div className="pt-6"><LoadingState label="Memuat stream…" /></div>;

  const epNum = Number((episodeId.match(/episode[-_ ]?(\d+)/i) ?? [])[1]);
  const episodes = info ? [...info.episodes].sort((a, b) => a.number - b.number) : [];
  const idx = episodes.findIndex((e) => e.id === episodeId);
  const prev = idx > 0 ? episodes[idx - 1] : undefined;
  const next = idx >= 0 && idx < episodes.length - 1 ? episodes[idx + 1] : undefined;

  return (
    <div className="pt-6">
      <Link href={info ? `/anime/${info.provider}/${encodeURIComponent(info.id)}` : '/'} className="text-sm text-accent-400 hover:underline">
        ← {info ? info.title : 'Kembali'}
      </Link>
      <h1 className="mt-2 text-lg font-bold sm:text-xl">{watch.title ?? episodeId}</h1>

      <div className="mt-4">
        <VideoPlayer
          data={watch}
          provider={provider}
          animeId={info?.id ?? episodeId}
          animeTitle={info?.title ?? watch.title ?? episodeId}
          animeImage={info?.image ?? ''}
          episodeNumber={Number.isFinite(epNum) ? epNum : undefined}
        />
      </div>

      {(prev || next) && (
        <div className="mt-4 flex gap-2">
          {prev && (
            <Link href={`/watch/${provider}/${encodeURIComponent(prev.id)}`} className="flex-1 rounded-lg border border-base-600 px-4 py-2 text-center text-sm hover:border-accent-500">
              ← EP {prev.number}
            </Link>
          )}
          {next && (
            <Link href={`/watch/${provider}/${encodeURIComponent(next.id)}`} className="flex-1 rounded-lg bg-accent-600 px-4 py-2 text-center text-sm font-semibold hover:bg-accent-500">
              EP {next.number} →
            </Link>
          )}
        </div>
      )}

      <section className="mt-8">
        <h2 className="mb-3 text-lg font-bold">Unduhan</h2>
        {downloads === null ? (
          <LoadingState label="Memuat link unduhan…" />
        ) : (
          <DownloadSection groups={downloads} />
        )}
      </section>

      {downloads !== null && (
        <section className="mt-6">
          <DebridPanel
            magnets={downloads.flatMap((g) => g.links.map((l) => l.url)).filter((u) => u.startsWith('magnet:'))}
            provider={provider}
            animeId={info?.id ?? episodeId}
            animeTitle={info?.title ?? watch.title ?? episodeId}
            animeImage={info?.image ?? ''}
          />
        </section>
      )}

      {episodes.length > 0 && (
        <section className="mt-8">
          <h2 className="mb-3 text-lg font-bold">Episode lain</h2>
          <EpisodeList provider={provider} episodes={episodes} />
        </section>
      )}
    </div>
  );
}
