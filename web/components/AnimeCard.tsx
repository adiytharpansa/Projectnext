'use client';

import Image from 'next/image';
import Link from 'next/link';
import type { AnimeSearchResult } from '@/lib/types';
import type { HistoryItem, WatchlistItem } from '@/lib/watchlist';

type CardItem =
  | AnimeSearchResult
  | (WatchlistItem & { id?: string })
  | (HistoryItem & { id?: string });

function hrefOf(item: CardItem): string {
  const animeId = 'animeId' in item ? item.animeId : item.id;
  return `/anime/${item.provider}/${encodeURIComponent(animeId)}`;
}

function imageOf(item: CardItem): string {
  return item.image || '/placeholder.png';
}

export default function AnimeCard({ item, badge }: { item: CardItem; badge?: string }) {
  return (
    <Link
      href={hrefOf(item)}
      className="group overflow-hidden rounded-xl border border-base-700/60 bg-base-800 transition hover:-translate-y-0.5 hover:border-accent-500/60"
    >
      <div className="relative aspect-[3/4] w-full bg-base-700">
        {item.image ? (
          <Image
            src={imageOf(item)}
            alt={item.title}
            fill
            sizes="(max-width: 640px) 33vw, (max-width: 1024px) 20vw, 160px"
            className="object-cover transition group-hover:scale-105"
            loading="lazy"
          />
        ) : (
          <div className="grid h-full place-items-center text-2xl">🎬</div>
        )}
        {badge && (
          <span className="absolute left-1.5 top-1.5 rounded-md bg-black/70 px-1.5 py-0.5 text-[11px] font-semibold text-accent-400">
            {badge}
          </span>
        )}
        {'score' in item && item.score && (
          <span className="absolute right-1.5 top-1.5 rounded-md bg-black/70 px-1.5 py-0.5 text-[11px] font-semibold text-amber-300">
            ★ {item.score}
          </span>
        )}
      </div>
      <div className="p-2">
        <p className="line-clamp-2 min-h-[2.5rem] text-xs font-semibold leading-snug">{item.title}</p>
        <p className="mt-1 text-[11px] uppercase tracking-wide text-slate-500">{item.provider}</p>
      </div>
    </Link>
  );
}

export function AnimeGrid({ items, badgeOf }: { items: CardItem[]; badgeOf?: (i: CardItem) => string | undefined }) {
  return (
    <div className="grid grid-cols-3 gap-3 sm:grid-cols-4 sm:gap-4 lg:grid-cols-6">
      {items.map((item, idx) => (
        <AnimeCard
          key={`${item.provider}-${'animeId' in item ? item.animeId : item.id}-${idx}`}
          item={item}
          badge={badgeOf?.(item)}
        />
      ))}
    </div>
  );
}

export function CardSkeletonGrid({ count = 12 }: { count?: number }) {
  return (
    <div className="grid grid-cols-3 gap-3 sm:grid-cols-4 sm:gap-4 lg:grid-cols-6">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="overflow-hidden rounded-xl border border-base-700/60 bg-base-800">
          <div className="aspect-[3/4] animate-pulse bg-base-700" />
          <div className="space-y-2 p-2">
            <div className="h-3 animate-pulse rounded bg-base-600" />
            <div className="h-3 w-2/3 animate-pulse rounded bg-base-600" />
          </div>
        </div>
      ))}
    </div>
  );
}
