'use client';

import Link from 'next/link';
import type { AnimeEpisode } from '@/lib/types';

export default function EpisodeList({
  provider,
  episodes,
  columns = 'grid',
}: {
  provider: string;
  episodes: AnimeEpisode[];
  columns?: 'grid' | 'list';
}) {
  if (episodes.length === 0) {
    return <p className="py-6 text-center text-sm text-slate-400">Belum ada episode.</p>;
  }
  if (columns === 'list') {
    return (
      <ul className="divide-y divide-base-700/60 overflow-hidden rounded-xl border border-base-700/60 bg-base-800">
        {episodes.map((ep) => (
          <li key={ep.id}>
            <Link
              href={`/watch/${provider}/${encodeURIComponent(ep.id)}`}
              className="flex items-center gap-3 px-4 py-3 transition hover:bg-base-700/60"
            >
              <span className="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-accent-600/20 text-sm font-bold text-accent-400">
                {ep.number}
              </span>
              <span className="min-w-0">
                <span className="block truncate text-sm font-medium">{ep.title ?? `Episode ${ep.number}`}</span>
                {ep.date && <span className="text-xs text-slate-500">{ep.date}</span>}
              </span>
              <span className="ml-auto text-slate-500">▶</span>
            </Link>
          </li>
        ))}
      </ul>
    );
  }
  return (
    <div className="grid grid-cols-4 gap-2 sm:grid-cols-6 lg:grid-cols-8">
      {episodes.map((ep) => (
        <Link
          key={ep.id}
          href={`/watch/${provider}/${encodeURIComponent(ep.id)}`}
          className="rounded-lg border border-base-600 bg-base-800 px-2 py-2.5 text-center text-sm font-semibold transition hover:border-accent-500 hover:bg-accent-600/20"
        >
          {ep.number}
        </Link>
      ))}
    </div>
  );
}
