'use client';

import { useEffect, useState } from 'react';
import { isInWatchlist, toggleWatchlist } from '@/lib/watchlist';

export default function WatchlistButton({
  provider,
  animeId,
  title,
  image,
}: {
  provider: string;
  animeId: string;
  title: string;
  image: string;
}) {
  const [saved, setSaved] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    isInWatchlist(provider, animeId).then(setSaved).catch(() => {});
  }, [provider, animeId]);

  return (
    <button
      disabled={busy}
      onClick={async () => {
        setBusy(true);
        try {
          setSaved(await toggleWatchlist({ provider, animeId, title, image }));
        } catch {
          alert('Gagal menyimpan watchlist');
        } finally {
          setBusy(false);
        }
      }}
      className={`rounded-lg px-4 py-2 text-sm font-semibold transition ${
        saved ? 'bg-amber-500/20 text-amber-300 border border-amber-500/50' : 'bg-base-700 hover:bg-base-600'
      }`}
    >
      {saved ? '★ Favorit' : '☆ Favorit'}
    </button>
  );
}
