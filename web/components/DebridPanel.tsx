'use client';

import { useEffect, useRef, useState } from 'react';
import VideoPlayer from './VideoPlayer';
import { ApiError, debridStatus, pollDebrid, unrestrictMagnet, type DebridResult, type DebridStatus } from '@/lib/api';
import type { WatchData } from '@/lib/types';

type Phase = 'checking' | 'disabled' | 'idle' | 'working' | 'ready' | 'error';

const POLL_MS = 10_000;
const MAX_POLLS = 60; // ~10 menit; user bisa lanjutkan manual

function shortMagnet(magnet: string): string {
  const m = magnet.match(/btih:([a-fA-F0-9]{6})[a-fA-F0-9]*/);
  const dn = magnet.match(/[?&]dn=([^&]*)/);
  const name = dn ? decodeURIComponent(dn[1]).slice(0, 42) : m ? `btih:${m[1]}…` : 'magnet';
  return name;
}

/**
 * DebridPanel — streaming torrent GRATIS via TorBox:
 * magnet → (cek cache → antre → poll) → link HTTP → VideoPlayer.
 * Muncul di watch page bila ada magnet dari Nyaa/Torrentio.
 */
export default function DebridPanel({
  magnets,
  provider,
  animeId,
  animeTitle,
  animeImage,
}: {
  magnets: string[];
  provider: string;
  animeId: string;
  animeTitle: string;
  animeImage: string;
}) {
  const [phase, setPhase] = useState<Phase>('checking');
  const [status, setStatus] = useState<DebridStatus | null>(null);
  const [magnetIdx, setMagnetIdx] = useState(0);
  const [result, setResult] = useState<DebridResult | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [polls, setPolls] = useState(0);
  const timer = useRef<number | null>(null);

  useEffect(() => {
    debridStatus()
      .then((s) => {
        setStatus(s);
        setPhase(s.configured ? 'idle' : 'disabled');
      })
      .catch(() => setPhase('disabled'));
    return () => {
      if (timer.current) window.clearInterval(timer.current);
    };
  }, []);

  if (magnets.length === 0 || phase === 'checking') return null;
  if (phase === 'disabled') return null; // backend tanpa TORBOX_API_KEY → sembunyi rapi

  const stopPoll = () => {
    if (timer.current) {
      window.clearInterval(timer.current);
      timer.current = null;
    }
  };

  const startPoll = (torrentId: number) => {
    stopPoll();
    setPolls(0);
    let n = 0;
    timer.current = window.setInterval(async () => {
      n += 1;
      setPolls(n);
      try {
        const r = await pollDebrid(torrentId);
        setResult(r);
        if (r.state === 'ready') {
          stopPoll();
          setPhase('ready');
        } else if (n >= MAX_POLLS) {
          stopPoll();
          setMessage('Masih mengunduh — biarkan berjalan, lalu tekan "Cek lagi".');
          setPhase('working');
        }
      } catch (e) {
        stopPoll();
        setMessage(e instanceof ApiError ? e.message : 'Polling gagal');
        setPhase('error');
      }
    }, POLL_MS);
  };

  const start = async () => {
    stopPoll();
    setPhase('working');
    setMessage(null);
    setResult(null);
    try {
      const r = await unrestrictMagnet(magnets[Math.min(magnetIdx, magnets.length - 1)]);
      setResult(r);
      if (r.state === 'ready') {
        setPhase('ready');
      } else if (r.torrentId !== undefined) {
        setMessage(r.note ?? 'Menunggu TorBox…');
        startPoll(r.torrentId);
      } else {
        setMessage(r.note ?? 'Tidak ada file video.');
        setPhase('error');
      }
    } catch (e) {
      setMessage(e instanceof ApiError ? e.message : 'Debrid gagal');
      setPhase('error');
    }
  };

  const readyData: WatchData | null =
    phase === 'ready' && result?.streamUrl
      ? {
          provider: 'torbox',
          episodeId: `debrid:${result.torrentId ?? 'x'}`,
          title: result.file?.name ?? animeTitle,
          sources: [
            { url: result.streamUrl, type: 'mp4', quality: 'debrid', server: 'TorBox' },
          ],
          subtitles: [],
        }
      : null;

  return (
    <div className="overflow-hidden rounded-xl border border-emerald-600/40 bg-base-800">
      <div className="flex items-center gap-2 border-b border-base-700/60 px-4 py-3">
        <h3 className="text-sm font-bold">⚡ Streaming torrent gratis</h3>
        <span className="rounded-full bg-emerald-600/20 px-2 py-0.5 text-[11px] font-semibold text-emerald-300">
          TorBox Free
        </span>
      </div>
      <div className="space-y-3 px-4 py-3">
        <p className="text-xs leading-relaxed text-slate-400">
          Mengubah magnet jadi link HTTP yang bisa diputar. Batas gratis: maks 10GB, 1 unduhan/24 jam,
          10/bulan — file yang sudah cached langsung siap tanpa antre.
        </p>

        {magnets.length > 1 && phase !== 'ready' && (
          <select
            value={magnetIdx}
            onChange={(e) => setMagnetIdx(Number(e.target.value))}
            className="w-full rounded-lg border border-base-600 bg-base-900 px-2 py-2 text-xs"
            aria-label="Pilih torrent"
          >
            {magnets.map((m, i) => (
              <option key={i} value={i}>
                {i + 1}. {shortMagnet(m)}
              </option>
            ))}
          </select>
        )}

        {phase !== 'ready' && (
          <button
            onClick={start}
            disabled={phase === 'working'}
            className="w-full rounded-lg bg-emerald-600 px-4 py-2.5 text-sm font-bold transition hover:bg-emerald-500 disabled:opacity-60 sm:w-auto"
          >
            {phase === 'working' ? 'Memproses…' : '▶ Dapatkan link stream'}
          </button>
        )}

        {(phase === 'working' || phase === 'error') && (
          <div className="rounded-lg bg-base-900 px-3 py-2.5 text-xs">
            {phase === 'working' && (
              <div className="flex items-center gap-2 text-slate-300">
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-base-600 border-t-emerald-400" />
                {result?.state === 'downloading'
                  ? `Mengunduh ${Math.round((result.progress ?? 0) * 100)}% (cek ${polls}×)…`
                  : (message ?? 'Menyiapkan…')}
                <button onClick={stopPoll} className="ml-auto text-slate-500 hover:text-white">
                  Hentikan
                </button>
              </div>
            )}
            {phase === 'error' && <p className="text-red-300">{message}</p>}
            {phase === 'working' && message && result?.state !== 'downloading' && (
              <div className="mt-2 flex gap-2">
                <button
                  onClick={() => result?.torrentId !== undefined && startPoll(result.torrentId)}
                  className="rounded-lg border border-base-600 px-3 py-1.5 hover:border-emerald-500"
                >
                  Cek lagi
                </button>
              </div>
            )}
          </div>
        )}

        {readyData && (
          <div>
            <VideoPlayer
              data={readyData}
              provider={provider}
              animeId={animeId}
              animeTitle={animeTitle}
              animeImage={animeImage}
            />
            <p className="mt-2 text-[11px] text-slate-500">
              Link CDN TorBox kedaluwarsa ±3 jam — putar atau unduh segera.
            </p>
          </div>
        )}
      </div>
      {status && (
        <p className="border-t border-base-700/60 px-4 py-2 text-[11px] text-slate-600">
          {status.limits.maxSize} • {status.limits.adds} • {status.limits.slots}
        </p>
      )}
    </div>
  );
}
