'use client';

import Image from 'next/image';
import { use, useCallback, useEffect, useState } from 'react';
import EpisodeList from '@/components/EpisodeList';
import { ErrorState, LoadingState } from '@/components/StateViews';
import WatchlistButton from '@/components/WatchlistButton';
import { ApiError, fetchAnimeInfo } from '@/lib/api';
import type { AnimeInfo } from '@/lib/types';

export const runtime = 'edge';

export default function AnimeDetailPage({
  params,
}: {
  params: Promise<{ provider: string; id: string }>;
}) {
  const { provider: rawProvider, id: rawId } = use(params);
  const provider = decodeURIComponent(rawProvider);
  const id = decodeURIComponent(rawId);
  const [info, setInfo] = useState<AnimeInfo | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [view, setView] = useState<'grid' | 'list'>('grid');

  const load = useCallback(async () => {
    setInfo(null);
    setError(null);
    try {
      setInfo(await fetchAnimeInfo(provider, id));
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Gagal memuat detail anime');
    }
  }, [provider, id]);

  useEffect(() => {
    load();
  }, [load]);

  if (error) return <div className="pt-6"><ErrorState message={error} retry={load} /></div>;
  if (!info) return <div className="pt-6"><LoadingState label="Memuat detail anime…" /></div>;

  return (
    <div className="pt-6">
      <div className="flex flex-col gap-5 sm:flex-row">
        <div className="relative mx-auto aspect-[3/4] w-44 shrink-0 overflow-hidden rounded-xl border border-base-700 sm:mx-0 sm:w-52">
          {info.image ? (
            <Image src={info.image} alt={info.title} fill sizes="208px" className="object-cover" priority />
          ) : (
            <div className="grid h-full place-items-center text-4xl">🎬</div>
          )}
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[11px] uppercase tracking-widest text-accent-400">{info.provider}</p>
          <h1 className="mt-1 text-xl font-black leading-tight sm:text-2xl">{info.title}</h1>
          <div className="mt-2 flex flex-wrap gap-1.5">
            {info.genres?.map((g) => (
              <span key={g} className="rounded-full bg-base-700 px-2.5 py-1 text-[11px] text-slate-200">
                {g}
              </span>
            ))}
          </div>
          <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm sm:max-w-md">
            {info.status && (<><dt className="text-slate-500">Status</dt><dd>{info.status}</dd></>)}
            {info.type && (<><dt className="text-slate-500">Tipe</dt><dd>{info.type}</dd></>)}
            {info.releaseDate && (<><dt className="text-slate-500">Rilis</dt><dd>{info.releaseDate}</dd></>)}
            {info.score && (<><dt className="text-slate-500">Skor</dt><dd>★ {info.score}</dd></>)}
            <dt className="text-slate-500">Episode</dt><dd>{info.totalEpisodes}</dd>
          </dl>
          <div className="mt-4">
            <WatchlistButton provider={info.provider} animeId={info.id} title={info.title} image={info.image} />
          </div>
        </div>
      </div>

      {info.description && (
        <section className="mt-6">
          <h2 className="mb-2 text-lg font-bold">Sinopsis</h2>
          <p className="text-sm leading-relaxed text-slate-300">{info.description}</p>
        </section>
      )}

      <section className="mt-6">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-lg font-bold">Daftar episode ({info.episodes.length})</h2>
          <div className="flex gap-1 rounded-lg bg-base-800 p-1 text-xs">
            {(['grid', 'list'] as const).map((v) => (
              <button
                key={v}
                onClick={() => setView(v)}
                className={`rounded-md px-3 py-1 font-semibold ${view === v ? 'bg-accent-600 text-white' : 'text-slate-400'}`}
              >
                {v === 'grid' ? 'Grid' : 'List'}
              </button>
            ))}
          </div>
        </div>
        <EpisodeList provider={info.provider} episodes={[...info.episodes].sort((a, b) => a.number - b.number)} columns={view} />
      </section>
    </div>
  );
}
