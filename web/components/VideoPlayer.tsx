'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Hls from 'hls.js';
import { proxiedStreamUrl } from '@/lib/api';
import { formatSeconds, levelLabel } from '@/lib/media';
import type { SubtitleTrack, VideoSource, WatchData } from '@/lib/types';
import { saveHistory } from '@/lib/watchlist';

type MenuKind = null | 'server' | 'quality' | 'subtitle' | 'speed';

const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 2];
const HIDE_DELAY_MS = 3000;

function isDirect(s: VideoSource): boolean {
  return !s.isEmbed && (s.type === 'hls' || s.type === 'mp4');
}

/**
 * VideoPlayer my-anime — kontrol kustom penuh:
 * play/pause, seekbar + buffer, durasi, volume, fullscreen,
 * kualitas (level HLS), subtitle (track), kecepatan, dan pindah server.
 *
 * Anti-gagal: .m3u8 selalu lewat /api/proxy/m3u8 backend (rewrite segmen +
 * suntik Referer). MP4 diputar langsung agar range-request/seek tetap jalan.
 */
export default function VideoPlayer({
  data,
  provider,
  animeId,
  animeTitle,
  animeImage,
  episodeNumber,
}: {
  data: WatchData;
  provider: string;
  animeId: string;
  animeTitle: string;
  animeImage: string;
  episodeNumber?: number;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const hideTimer = useRef<number | null>(null);

  const [sourceIdx, setSourceIdx] = useState(0);
  const [reloadKey, setReloadKey] = useState(0);
  const [levels, setLevels] = useState<{ index: number; height?: number; bitrate?: number }[]>([]);
  const [level, setLevel] = useState(-1); // -1 = Auto
  const [speed, setSpeed] = useState(1);
  const [subtitleIdx, setSubtitleIdx] = useState(-1); // -1 = Mati

  const [playing, setPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [buffered, setBuffered] = useState(0);
  const [volume, setVolume] = useState(1);
  const [muted, setMuted] = useState(false);
  const [waiting, setWaiting] = useState(true);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [controlsVisible, setControlsVisible] = useState(true);
  const [openMenu, setOpenMenu] = useState<MenuKind>(null);
  const [error, setError] = useState<string | null>(null);

  const playable = useMemo(() => {
    const direct = data.sources.filter(isDirect);
    return direct.length > 0 ? direct : data.sources;
  }, [data.sources]);
  const current: VideoSource | undefined = playable[Math.min(sourceIdx, playable.length - 1)];
  const referer = data.headers?.Referer ?? data.embedUrl;
  const subtitles: SubtitleTrack[] = data.subtitles ?? [];

  // ── Reset saat ganti episode ──
  useEffect(() => {
    setSourceIdx(0);
    setReloadKey(0);
    setLevel(-1);
    setSpeed(1);
    setSubtitleIdx(-1);
    setLevels([]);
    setError(null);
    setTime(0);
    setDuration(0);
    setBuffered(0);
    setPlaying(false);
    setWaiting(true);
  }, [data.episodeId]);

  const pokeControls = useCallback(() => {
    setControlsVisible(true);
    if (hideTimer.current) window.clearTimeout(hideTimer.current);
    hideTimer.current = window.setTimeout(() => {
      if (videoRef.current && !videoRef.current.paused) setControlsVisible(false);
    }, HIDE_DELAY_MS);
  }, []);

  useEffect(() => () => {
    if (hideTimer.current) window.clearTimeout(hideTimer.current);
  }, []);

  // ── Muat sumber ke <video> ──
  useEffect(() => {
    const video = videoRef.current;
    if (!video || !current || current.isEmbed || current.type === 'embed') return;
    setError(null);
    setWaiting(true);

    const src =
      current.type === 'hls' ? proxiedStreamUrl(current.url, referer) : current.url;

    const onPlay = () => {
      setPlaying(true);
      pokeControls();
    };
    const onPause = () => {
      setPlaying(false);
      setControlsVisible(true);
    };
    const onTime = () => setTime(video.currentTime);
    const onDuration = () => setDuration(video.duration || 0);
    const onProgress = () => {
      try {
        if (video.buffered.length > 0) setBuffered(video.buffered.end(video.buffered.length - 1));
      } catch {
        /* abaikan */
      }
    };
    const onWaiting = () => setWaiting(true);
    const onPlaying = () => setWaiting(false);
    const onEnded = () => {
      setPlaying(false);
      setControlsVisible(true);
    };
    const onVolume = () => {
      setVolume(video.volume);
      setMuted(video.muted);
    };
    const onRate = () => setSpeed(video.playbackRate);
    const onError = () => {
      if (video.error) setError('Video gagal dimuat dari server ini. Coba server lain.');
    };

    video.addEventListener('play', onPlay);
    video.addEventListener('pause', onPause);
    video.addEventListener('timeupdate', onTime);
    video.addEventListener('durationchange', onDuration);
    video.addEventListener('progress', onProgress);
    video.addEventListener('waiting', onWaiting);
    video.addEventListener('playing', onPlaying);
    video.addEventListener('ended', onEnded);
    video.addEventListener('volumechange', onVolume);
    video.addEventListener('ratechange', onRate);
    video.addEventListener('error', onError);

    video.playbackRate = speed;

    if (current.type === 'hls' && Hls.isSupported()) {
      const hls = new Hls({ maxBufferLength: 30 });
      hlsRef.current = hls;
      hls.loadSource(src);
      hls.attachMedia(video);
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        setLevels(hls.levels.map((l, index) => ({ index, height: l.height, bitrate: l.bitrate })));
        video.play().catch(() => {});
      });
      hls.on(Hls.Events.ERROR, (_, err) => {
        if (!err.fatal) return;
        // Satu kali coba pulih, selebihnya tampilkan error + opsi ganti server.
        if (err.type === Hls.ErrorTypes.MEDIA_ERROR) {
          hls.recoverMediaError();
        } else {
          setError('Stream gagal dimuat. Coba server lain di bawah.');
          setWaiting(false);
        }
      });
    } else {
      // Safari (HLS native) atau MP4 langsung.
      video.src = src;
      video.load();
      video.play().catch(() => {});
    }

    const tick = window.setInterval(() => {
      if (!video.paused && video.currentTime > 5) {
        saveHistory({
          provider,
          animeId,
          episodeId: data.episodeId,
          episodeNumber,
          title: data.title ?? animeTitle,
          image: animeImage,
          progressSeconds: Math.floor(video.currentTime),
        }).catch(() => {});
      }
    }, 10_000);

    return () => {
      window.clearInterval(tick);
      video.removeEventListener('play', onPlay);
      video.removeEventListener('pause', onPause);
      video.removeEventListener('timeupdate', onTime);
      video.removeEventListener('durationchange', onDuration);
      video.removeEventListener('progress', onProgress);
      video.removeEventListener('waiting', onWaiting);
      video.removeEventListener('playing', onPlaying);
      video.removeEventListener('ended', onEnded);
      video.removeEventListener('volumechange', onVolume);
      video.removeEventListener('ratechange', onRate);
      video.removeEventListener('error', onError);
      hlsRef.current?.destroy();
      hlsRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [current, reloadKey, data.episodeId]);

  // ── Terapkan level kualitas manual ──
  useEffect(() => {
    const hls = hlsRef.current;
    if (!hls) return;
    hls.nextLevel = level;
  }, [level]);

  // ── Terapkan subtitle aktif ──
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const tracks = video.textTracks;
    for (let i = 0; i < tracks.length; i++) {
      tracks[i].mode = i === subtitleIdx ? 'showing' : 'disabled';
    }
  }, [subtitleIdx, current, reloadKey]);

  // ── Fullscreen ──
  useEffect(() => {
    const onFs = () => setIsFullscreen(Boolean(document.fullscreenElement));
    document.addEventListener('fullscreenchange', onFs);
    return () => document.removeEventListener('fullscreenchange', onFs);
  }, []);

  const toggleFullscreen = useCallback(() => {
    if (document.fullscreenElement) {
      document.exitFullscreen().catch(() => {});
    } else {
      containerRef.current?.requestFullscreen().catch(() => {});
    }
  }, []);

  const togglePlay = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) video.play().catch(() => {});
    else video.pause();
  }, []);

  const seekBy = useCallback(
    (delta: number) => {
      const video = videoRef.current;
      if (!video || !Number.isFinite(video.duration)) return;
      video.currentTime = Math.min(Math.max(0, video.currentTime + delta), video.duration);
      pokeControls();
    },
    [pokeControls],
  );

  const switchServer = useCallback(
    (idx: number) => {
      setSourceIdx(idx);
      setLevel(-1);
      setLevels([]);
      setSubtitleIdx(-1);
      setOpenMenu(null);
      pokeControls();
    },
    [pokeControls],
  );

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === ' ') {
      e.preventDefault();
      togglePlay();
    } else if (e.key === 'ArrowRight') seekBy(10);
    else if (e.key === 'ArrowLeft') seekBy(-10);
    else if (e.key.toLowerCase() === 'f') toggleFullscreen();
    else if (e.key.toLowerCase() === 'm' && videoRef.current) videoRef.current.muted = !muted;
  };

  if (!current) {
    return <p className="py-10 text-center text-sm text-slate-400">Tidak ada stream tersedia.</p>;
  }

  // ── Embed tak ter-resolve → iframe ──
  if (current.isEmbed || current.type === 'embed') {
    return (
      <div>
        <div className="overflow-hidden rounded-xl border border-base-700 bg-black">
          <iframe
            src={current.url}
            className="aspect-video w-full"
            allowFullScreen
            allow="autoplay; encrypted-media"
            title={data.title ?? data.episodeId}
          />
        </div>
        <EmbedFallback
          server={current.server}
          alternatives={playable.length - 1}
          onNext={() => switchServer((sourceIdx + 1) % playable.length)}
        />
      </div>
    );
  }

  const bufferedPct = duration > 0 ? Math.min(100, (buffered / duration) * 100) : 0;
  const playedPct = duration > 0 ? Math.min(100, (time / duration) * 100) : 0;

  return (
    <div>
      <div
        ref={containerRef}
        tabIndex={0}
        onKeyDown={onKeyDown}
        onMouseMove={pokeControls}
        onTouchStart={pokeControls}
        className={`group relative select-none overflow-hidden rounded-xl border border-base-700 bg-black outline-none ${
          controlsVisible ? '' : 'cursor-none'
        }`}
      >
        <video
          ref={videoRef}
          playsInline
          crossOrigin="anonymous"
          preload="metadata"
          poster={animeImage}
          className="aspect-video w-full"
          onClick={togglePlay}
          onDoubleClick={toggleFullscreen}
        >
          {subtitles.map((t, i) => (
            <track
              key={`${t.url}-${i}`}
              kind="subtitles"
              src={proxiedStreamUrl(t.url, referer)}
              srcLang={(t.lang || 'en').slice(0, 2).toLowerCase()}
              label={t.label || t.lang}
            />
          ))}
        </video>

        {/* Spinner buffering */}
        {waiting && !error && (
          <div className="pointer-events-none absolute inset-0 grid place-items-center">
            <div className="h-12 w-12 animate-spin rounded-full border-[3px] border-white/20 border-t-accent-400" />
          </div>
        )}

        {/* Tombol play raksasa saat jeda */}
        {!playing && !waiting && !error && (
          <button
            onClick={togglePlay}
            aria-label="Putar"
            className="absolute inset-0 grid place-items-center bg-black/30 transition hover:bg-black/40"
          >
            <span className="grid h-16 w-16 place-items-center rounded-full bg-accent-600/90 text-2xl text-white shadow-lg transition hover:scale-105">
              ▶
            </span>
          </button>
        )}

        {/* Overlay error */}
        {error && (
          <div className="absolute inset-0 grid place-items-center bg-black/80 p-6 text-center">
            <div>
              <div className="text-4xl">📡</div>
              <p className="mx-auto mt-3 max-w-sm text-sm text-slate-200">{error}</p>
              <p className="mt-1 text-xs text-slate-500">
                Server: {current.server ?? 'default'} • {current.quality} • {current.type.toUpperCase()}
              </p>
              <div className="mt-4 flex justify-center gap-2">
                <button
                  onClick={() => setReloadKey((k) => k + 1)}
                  className="rounded-lg bg-accent-600 px-4 py-2 text-sm font-semibold transition hover:bg-accent-500"
                >
                  Coba lagi
                </button>
                {playable.length > 1 && (
                  <button
                    onClick={() => switchServer((sourceIdx + 1) % playable.length)}
                    className="rounded-lg border border-base-600 px-4 py-2 text-sm transition hover:border-accent-500"
                  >
                    Server lain
                  </button>
                )}
              </div>
            </div>
          </div>
        )}

        {/* Kontrol bawah */}
        <div
          className={`absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/90 via-black/60 to-transparent px-3 pb-2.5 pt-8 transition-opacity duration-300 sm:px-4 ${
            controlsVisible ? 'opacity-100' : 'pointer-events-none opacity-0'
          }`}
        >
          {/* Seekbar */}
          <div className="relative h-5 items-center">
            <div className="absolute inset-x-0 top-1/2 h-1 -translate-y-1/2 overflow-hidden rounded-full bg-white/20">
              <div className="h-full rounded-full bg-white/30 transition-all" style={{ width: `${bufferedPct}%` }} />
            </div>
            <div
              className="absolute left-0 top-1/2 h-1 -translate-y-1/2 rounded-full bg-accent-500 transition-all"
              style={{ width: `${playedPct}%` }}
            />
            <input
              type="range"
              min={0}
              max={duration || 0}
              step={0.1}
              value={Number.isFinite(time) ? time : 0}
              onChange={(e) => {
                const v = videoRef.current;
                if (v) v.currentTime = Number(e.target.value);
              }}
              aria-label="Cari posisi"
              className="absolute inset-x-0 top-1/2 h-5 w-full -translate-y-1/2 cursor-pointer opacity-0"
            />
            {/* knob */}
            <div
              className="pointer-events-none absolute top-1/2 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full bg-accent-400 shadow"
              style={{ left: `${playedPct}%` }}
            />
          </div>

          <div className="mt-0.5 flex items-center gap-1 sm:gap-2">
            <IconButton label={playing ? 'Jeda' : 'Putar'} onClick={togglePlay}>
              {playing ? '⏸' : '▶'}
            </IconButton>
            <IconButton label="Mundur 10 dtk" onClick={() => seekBy(-10)}>
              ↺
            </IconButton>
            <IconButton label="Maju 10 dtk" onClick={() => seekBy(10)}>
              ↻
            </IconButton>
            <span className="ml-1 whitespace-nowrap text-[11px] tabular-nums text-slate-200 sm:text-xs">
              {formatSeconds(time)} / {formatSeconds(duration)}
            </span>

            <div className="ml-auto flex items-center gap-1 sm:gap-2">
              {/* Volume (desktop) */}
              <div className="hidden items-center gap-1 sm:flex">
                <IconButton
                  label={muted || volume === 0 ? 'Suarakan' : 'Bisukan'}
                  onClick={() => {
                    const v = videoRef.current;
                    if (v) v.muted = !muted;
                  }}
                >
                  {muted || volume === 0 ? '🔇' : '🔊'}
                </IconButton>
                <input
                  type="range"
                  min={0}
                  max={1}
                  step={0.05}
                  value={muted ? 0 : volume}
                  onChange={(e) => {
                    const v = videoRef.current;
                    if (!v) return;
                    v.muted = false;
                    v.volume = Number(e.target.value);
                  }}
                  aria-label="Volume"
                  className="h-1 w-16 cursor-pointer accent-violet-500"
                />
              </div>

              <MenuButton label="Server" active={openMenu === 'server'} onClick={() => setOpenMenu(openMenu === 'server' ? null : 'server')}>
                🗄
              </MenuButton>
              {levels.length > 1 && (
                <MenuButton label={`Kualitas: ${level === -1 ? 'Auto' : levelLabel(levels[level] ?? {})}`} active={openMenu === 'quality'} onClick={() => setOpenMenu(openMenu === 'quality' ? null : 'quality')}>
                  ⚙
                </MenuButton>
              )}
              {subtitles.length > 0 && (
                <MenuButton label="Subtitle" active={openMenu === 'subtitle'} onClick={() => setOpenMenu(openMenu === 'subtitle' ? null : 'subtitle')}>
                  💬
                </MenuButton>
              )}
              <MenuButton label={`Kecepatan: ${speed}x`} active={openMenu === 'speed'} onClick={() => setOpenMenu(openMenu === 'speed' ? null : 'speed')}>
                ⏩
              </MenuButton>
              <IconButton label={isFullscreen ? 'Keluar fullscreen' : 'Fullscreen'} onClick={toggleFullscreen}>
                {isFullscreen ? '⤓' : '⤢'}
              </IconButton>
            </div>
          </div>

          {/* Panel menu */}
          {openMenu && (
            <div className="absolute bottom-full right-2 mb-2 w-52 overflow-hidden rounded-xl border border-base-600 bg-base-900/95 shadow-xl backdrop-blur">
              {openMenu === 'server' && (
                <MenuList
                  title="Server"
                  options={playable.map((s, i) => ({
                    key: String(i),
                    label: `${s.server ?? 'Server'} • ${s.quality}`,
                    hint: s.type.toUpperCase(),
                    active: i === sourceIdx,
                    onPick: () => switchServer(i),
                  }))}
                />
              )}
              {openMenu === 'quality' && (
                <MenuList
                  title="Kualitas"
                  options={[
                    { key: 'auto', label: 'Auto', active: level === -1, onPick: () => { setLevel(-1); setOpenMenu(null); } },
                    ...levels.map((l) => ({
                      key: String(l.index),
                      label: levelLabel(l),
                      active: level === l.index,
                      onPick: () => { setLevel(l.index); setOpenMenu(null); },
                    })),
                  ]}
                />
              )}
              {openMenu === 'subtitle' && (
                <MenuList
                  title="Subtitle"
                  options={[
                    { key: 'off', label: 'Mati', active: subtitleIdx === -1, onPick: () => { setSubtitleIdx(-1); setOpenMenu(null); } },
                    ...subtitles.map((t, i) => ({
                      key: String(i),
                      label: t.label || t.lang,
                      hint: t.lang,
                      active: subtitleIdx === i,
                      onPick: () => { setSubtitleIdx(i); setOpenMenu(null); },
                    })),
                  ]}
                />
              )}
              {openMenu === 'speed' && (
                <MenuList
                  title="Kecepatan"
                  options={SPEEDS.map((s) => ({
                    key: String(s),
                    label: `${s}x`,
                    active: speed === s,
                    onPick: () => {
                      if (videoRef.current) videoRef.current.playbackRate = s;
                      setSpeed(s);
                      setOpenMenu(null);
                    },
                  }))}
                />
              )}
            </div>
          )}
        </div>
      </div>

      {/* Info server + pintasan proxy */}
      <div className="mt-3 flex flex-wrap items-center gap-2 text-xs text-slate-400">
        <span className="rounded-md bg-base-800 px-2 py-1">
          {current.server ?? 'Server'} • {current.quality} • {current.type.toUpperCase()}
          {current.type === 'hls' ? ' • via proxy' : ''}
        </span>
        <a
          href={proxiedStreamUrl(current.url, referer)}
          target="_blank"
          rel="noreferrer"
          className="rounded-md border border-base-600 px-2 py-1 transition hover:border-accent-500 hover:text-white"
        >
          Buka via proxy ↗
        </a>
      </div>
    </div>
  );
}

function IconButton({
  label,
  onClick,
  children,
}: {
  label: string;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      aria-label={label}
      title={label}
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
      className="grid h-9 w-9 place-items-center rounded-lg text-base text-white transition hover:bg-white/15"
    >
      {children}
    </button>
  );
}

function MenuButton({
  label,
  active,
  onClick,
  children,
}: {
  label: string;
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      aria-label={label}
      title={label}
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
      className={`grid h-9 w-9 place-items-center rounded-lg text-base transition ${
        active ? 'bg-accent-600 text-white' : 'text-white hover:bg-white/15'
      }`}
    >
      {children}
    </button>
  );
}

function MenuList({
  title,
  options,
}: {
  title: string;
  options: { key: string; label: string; hint?: string; active: boolean; onPick: () => void }[];
}) {
  return (
    <div className="max-h-56 overflow-y-auto p-1.5">
      <p className="px-2 pb-1 pt-1 text-[11px] font-bold uppercase tracking-widest text-slate-500">{title}</p>
      {options.map((o) => (
        <button
          key={o.key}
          onClick={o.onPick}
          className={`flex w-full items-center gap-2 rounded-lg px-2.5 py-2 text-left text-sm transition ${
            o.active ? 'bg-accent-600/25 text-white' : 'text-slate-300 hover:bg-white/10'
          }`}
        >
          <span className="min-w-0 flex-1 truncate">{o.label}</span>
          {o.hint && <span className="text-[11px] text-slate-500">{o.hint}</span>}
          {o.active && <span className="text-accent-400">✓</span>}
        </button>
      ))}
    </div>
  );
}

function EmbedFallback({
  server,
  alternatives,
  onNext,
}: {
  server?: string;
  alternatives: number;
  onNext: () => void;
}) {
  return (
    <div className="mt-2 flex flex-wrap items-center gap-2 rounded-xl border border-base-700/60 bg-base-800 px-3 py-2.5 text-xs text-slate-400">
      <span>
        Server embed ({server ?? 'default'}) dimuat langsung — bila gagal, gunakan proxy/download di bawah.
      </span>
      {alternatives > 0 && (
        <button
          onClick={onNext}
          className="ml-auto shrink-0 rounded-lg bg-accent-600/20 px-3 py-1.5 font-semibold text-accent-400 transition hover:bg-accent-600 hover:text-white"
        >
          Server lain
        </button>
      )}
    </div>
  );
}
