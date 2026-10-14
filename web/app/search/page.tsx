'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useCallback, useEffect, useState } from 'react';
import { AnimeGrid, CardSkeletonGrid } from '@/components/AnimeCard';
import { EmptyState, ErrorState } from '@/components/StateViews';
import { ApiError, searchAnime } from '@/lib/api';
import type { AnimeSearchResult } from '@/lib/types';

const PROVIDERS = [
  { id: '', label: 'Semua' },
  { id: 'gogo', label: 'Gogoanime' },
  { id: 'gogoby', label: 'Gogo.by' },
  { id: 'samehadaku', label: 'Samehadaku' },
  { id: 'crunchyroll', label: 'Crunchyroll' },
  { id: 'iqiyi', label: 'iQIYI' },
  { id: 'torrentio', label: 'Torrentio' },
  { id: 'nyaa', label: 'Nyaa' },
];

function SearchView() {
  const params = useSearchParams();
  const router = useRouter();
  const q = params.get('q') ?? '';
  const provider = params.get('provider') ?? '';
  const [input, setInput] = useState(q);
  const [results, setResults] = useState<AnimeSearchResult[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const run = useCallback(async (query: string, prov: string) => {
    if (!query.trim()) {
      setResults([]);
      return;
    }
    setResults(null);
    setError(null);
    try {
      const data = await searchAnime(query, prov || undefined);
      setResults(data.results);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Pencarian gagal');
    }
  }, []);

  useEffect(() => {
    setInput(q);
    run(q, provider);
  }, [q, provider, run]);

  return (
    <div className="pt-6">
      <form
        className="flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          const p = new URLSearchParams({ q: input.trim() });
          if (provider) p.set('provider', provider);
          router.push(`/search?${p.toString()}`);
        }}
      >
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Cari anime…"
          className="h-11 w-full rounded-xl border border-base-600 bg-base-800 px-4 text-sm outline-none placeholder:text-slate-500 focus:border-accent-500"
        />
        <button className="h-11 shrink-0 rounded-xl bg-accent-600 px-5 text-sm font-bold hover:bg-accent-500">
          Cari
        </button>
      </form>

      <div className="mt-3 flex gap-2">
        {PROVIDERS.map((p) => {
          const active = provider === p.id;
          const href = q
            ? `/search?q=${encodeURIComponent(q)}${p.id ? `&provider=${p.id}` : ''}`
            : `/search?provider=${p.id}`;
          return (
            <button
              key={p.id}
              onClick={() => router.push(href)}
              className={`rounded-full px-4 py-1.5 text-xs font-semibold ${
                active ? 'bg-accent-600 text-white' : 'bg-base-800 text-slate-300 hover:bg-base-700'
              }`}
            >
              {p.label}
            </button>
          );
        })}
      </div>

      <div className="mt-6">
        {!q.trim() && <EmptyState title="Ketik kata kunci dulu" hint="Hasil dari Gogoanime & Samehadaku tampil di sini." />}
        {q.trim() !== '' && results === null && !error && <CardSkeletonGrid />}
        {error && <ErrorState message={error} retry={() => run(q, provider)} />}
        {results !== null && !error && results.length === 0 && (
          <EmptyState title={`Tidak ada hasil untuk "${q}"`} hint="Coba kata kunci lain atau ganti provider." />
        )}
        {results !== null && results.length > 0 && (
          <>
            <p className="mb-3 text-sm text-slate-400">
              {results.length} hasil untuk <b className="text-white">“{q}”</b>
            </p>
            <AnimeGrid items={results} badgeOf={(r) => ('releaseDate' in r ? r.releaseDate : undefined)} />
          </>
        )}
      </div>
    </div>
  );
}

export default function SearchPage() {
  return (
    <Suspense>
      <SearchView />
    </Suspense>
  );
}
