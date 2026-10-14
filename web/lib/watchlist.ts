'use client';

/**
 * Penyimpanan watchlist & riwayat tontonan.
 * Supabase bila env dikonfigurasi, fallback localStorage bila tidak —
 * API-nya identik sehingga UI tidak perlu bercabang.
 */
import { deviceId, getSupabase } from './supabase';

export interface WatchlistItem {
  provider: string;
  animeId: string;
  title: string;
  image: string;
  addedAt: string;
}

export interface HistoryItem {
  provider: string;
  animeId: string;
  episodeId: string;
  episodeNumber?: number;
  title: string;
  image: string;
  progressSeconds?: number;
  updatedAt: string;
}

const LS_WATCHLIST = 'my-anime:watchlist';
const LS_HISTORY = 'my-anime:history';
const HISTORY_LIMIT = 30;

function readLS<T>(key: string, fallback: T): T {
  try {
    const raw = window.localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}

function writeLS(key: string, value: unknown): void {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    /* storage penuh — abaikan */
  }
}

// ── Watchlist ─────────────────────────────────────────────

export async function getWatchlist(): Promise<WatchlistItem[]> {
  const sb = getSupabase();
  if (!sb) return readLS<WatchlistItem[]>(LS_WATCHLIST, []);
  const { data, error } = await sb
    .from('watchlist')
    .select('provider, anime_id, title, image, created_at')
    .eq('user_id', deviceId())
    .order('created_at', { ascending: false });
  if (error) throw new Error(`Supabase: ${error.message}`);
  return (data ?? []).map((r) => ({
    provider: r.provider,
    animeId: r.anime_id,
    title: r.title,
    image: r.image,
    addedAt: r.created_at,
  }));
}

export async function isInWatchlist(provider: string, animeId: string): Promise<boolean> {
  const list = await getWatchlist();
  return list.some((i) => i.provider === provider && i.animeId === animeId);
}

export async function toggleWatchlist(item: Omit<WatchlistItem, 'addedAt'>): Promise<boolean> {
  const sb = getSupabase();
  const uid = deviceId();
  if (!sb) {
    const list = readLS<WatchlistItem[]>(LS_WATCHLIST, []);
    const idx = list.findIndex((i) => i.provider === item.provider && i.animeId === item.animeId);
    if (idx >= 0) {
      list.splice(idx, 1);
      writeLS(LS_WATCHLIST, list);
      return false;
    }
    list.unshift({ ...item, addedAt: new Date().toISOString() });
    writeLS(LS_WATCHLIST, list);
    return true;
  }
  const exists = await isInWatchlist(item.provider, item.animeId);
  if (exists) {
    const { error } = await sb
      .from('watchlist')
      .delete()
      .eq('user_id', uid)
      .eq('provider', item.provider)
      .eq('anime_id', item.animeId);
    if (error) throw new Error(`Supabase: ${error.message}`);
    return false;
  }
  const { error } = await sb.from('watchlist').insert({
    user_id: uid,
    provider: item.provider,
    anime_id: item.animeId,
    title: item.title,
    image: item.image,
  });
  if (error) throw new Error(`Supabase: ${error.message}`);
  return true;
}

// ── Riwayat ───────────────────────────────────────────────

export async function getHistory(): Promise<HistoryItem[]> {
  const sb = getSupabase();
  if (!sb) return readLS<HistoryItem[]>(LS_HISTORY, []);
  const { data, error } = await sb
    .from('history')
    .select('provider, anime_id, episode_id, episode_number, title, image, progress_seconds, updated_at')
    .eq('user_id', deviceId())
    .order('updated_at', { ascending: false })
    .limit(HISTORY_LIMIT);
  if (error) throw new Error(`Supabase: ${error.message}`);
  return (data ?? []).map((r) => ({
    provider: r.provider,
    animeId: r.anime_id,
    episodeId: r.episode_id,
    episodeNumber: r.episode_number ?? undefined,
    title: r.title,
    image: r.image,
    progressSeconds: r.progress_seconds ?? undefined,
    updatedAt: r.updated_at,
  }));
}

/** Catat／perbarui progres tontonan (dipanggil berkala dari VideoPlayer). */
export async function saveHistory(item: Omit<HistoryItem, 'updatedAt'>): Promise<void> {
  const sb = getSupabase();
  if (!sb) {
    const list = readLS<HistoryItem[]>(LS_HISTORY, []).filter(
      (h) => !(h.provider === item.provider && h.episodeId === item.episodeId),
    );
    list.unshift({ ...item, updatedAt: new Date().toISOString() });
    writeLS(LS_HISTORY, list.slice(0, HISTORY_LIMIT));
    return;
  }
  const { error } = await sb.from('history').upsert(
    {
      user_id: deviceId(),
      provider: item.provider,
      anime_id: item.animeId,
      episode_id: item.episodeId,
      episode_number: item.episodeNumber ?? null,
      title: item.title,
      image: item.image,
      progress_seconds: item.progressSeconds ?? 0,
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id,provider,episode_id' },
  );
  if (error) throw new Error(`Supabase: ${error.message}`);
}

export async function clearHistory(): Promise<void> {
  const sb = getSupabase();
  if (!sb) {
    writeLS(LS_HISTORY, []);
    return;
  }
  const { error } = await sb.from('history').delete().eq('user_id', deviceId());
  if (error) throw new Error(`Supabase: ${error.message}`);
}
