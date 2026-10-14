'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { AnimeGrid } from '@/components/AnimeCard';
import { ErrorState } from '@/components/StateViews';
import { clearHistory, getHistory, getWatchlist, type HistoryItem, type WatchlistItem } from '@/lib/watchlist';
import { isSupabaseConfigured } from '@/lib/supabase';

const SUGGESTIONS = ['Naruto', 'One Piece', 'Jujutsu Kaisen', 'Frieren', 'Solo Leveling', 'Dandadan'];

export default function HomePage() {
  const router = useRouter();
  const [q, setQ] = useState('');
  const [watchlist, setWatchlist] = useState<WatchlistItem[] | null>(null);
  const [history, setHistory] = useState<HistoryItem[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    Promise.all([getWatchlist().catch(() => null), getHistory().catch(() => null)]).then(
      ([w, h]) => {
        if (w === null && h === null) setFailed(true);
        setWatchlist(w ?? []);
        setHistory(h ?? []);
      },
    );
  }, []);

  return (
    <div className="pt-6">
      {/* Hero + pencarian */}
      <section className="overflow-hidden rounded-2xl border border-base-700/60 bg-gradient-to-br from-accent-600/30 via-base-800 to-base-900 p-6 sm:p-10">
        <h1 className="text-2xl font-black tracking-tight sm:text-4xl">
          Nonton & unduh anime favoritmu 🎬
        </h1>
        <p className="mt-2 max-w-lg text-sm text-slate-300 sm:text-base">
          Cari judul, pilih episode, streaming HLS anti-gagal via proxy, atau unduh per resolusi.
        </p>
        <form
          className="mt-5 flex max-w-lg gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (q.trim()) router.push(`/search?q=${encodeURIComponent(q.trim())}`);
          }}
        >
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="cth: Frieren…"
            className="h-11 w-full rounded-xl border border-base-600 bg-base-950/70 px-4 text-sm outline-none placeholder:text-slate-500 focus:border-accent-500"
          />
          <button className="h-11 shrink-0 rounded-xl bg-accent-600 px-5 text-sm font-bold hover:bg-accent-500">
            Cari
          </button>
        </form>
        <div className="mt-4 flex flex-wrap gap-2">
          {SUGGESTIONS.map((s) => (
            <Link
              key={s}
              href={`/search?q=${encodeURIComponent(s)}`}
              className="rounded-full border border-base-600 px-3 py-1 text-xs text-slate-300 hover:border-accent-500 hover:text-white"
            >
              {s}
            </Link>
          ))}
        </div>
        {!isSupabaseConfigured() && (
          <p className="mt-4 text-xs text-slate-500">
            Mode lokal: Supabase belum dikonfigurasi — favorit & riwayat tersimpan di browser ini.
          </p>
        )}
      </section>

      {/* Lanjutkan menonton */}
      {history !== null && history.length > 0 && (
        <section className="mt-8">
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-lg font-bold">Lanjutkan menonton</h2>
            <button
              className="text-xs text-slate-400 hover:text-white"
              onClick={() => clearHistory().then(() => setHistory([])).catch(() => {})}
            >
              Hapus riwayat
            </button>
          </div>
          <AnimeGrid items={history} badgeOf={(h) => ('episodeNumber' in h && h.episodeNumber ? `EP ${h.episodeNumber}` : undefined)} />
        </section>
      )}

      {/* Favorit */}
      {watchlist !== null && watchlist.length > 0 && (
        <section className="mt-8">
          <h2 className="mb-3 text-lg font-bold">Favorit saya ★</h2>
          <AnimeGrid items={watchlist} />
        </section>
      )}

      {failed && (
        <div className="mt-8">
          <ErrorState message="Gagal memuat data lokal." retry={() => window.location.reload()} />
        </div>
      )}

      {watchlist?.length === 0 && history?.length === 0 && (
        <section className="mt-8 rounded-2xl border border-dashed border-base-600 p-8 text-center text-sm text-slate-400">
          Mulai dengan mencari anime di atas — episode yang kamu tonton dan judul favorit akan muncul di sini.
        </section>
      )}
    </div>
  );
}
