'use client';

import { useMemo, useState } from 'react';
import { safeHostname, sortDownloadGroups } from '@/lib/media';
import type { DownloadGroup, DownloadLink } from '@/lib/types';

const SERVER_COLORS = [
  'bg-violet-600',
  'bg-sky-600',
  'bg-emerald-600',
  'bg-amber-600',
  'bg-rose-600',
  'bg-cyan-600',
];

function colorFor(name: string): string {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 997;
  return SERVER_COLORS[h % SERVER_COLORS.length];
}

async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    try {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      return true;
    } catch {
      return false;
    }
  }
}

/**
 * Download Center — link unduhan dikelompokkan per resolusi (tertinggi dulu),
 * tiap server tampil sebagai tombol interaktif + salin tautan.
 */
export default function DownloadSection({
  groups,
  title = 'Pusat Unduhan',
}: {
  groups: DownloadGroup[];
  title?: string;
}) {
  const sorted = useMemo(() => sortDownloadGroups(groups), [groups]);
  const formats = useMemo(() => {
    const seen: string[] = [];
    for (const g of sorted) {
      if (g.format && !seen.includes(g.format)) seen.push(g.format);
    }
    return seen;
  }, [sorted]);
  const [formatFilter, setFormatFilter] = useState<string>('all');
  const [open, setOpen] = useState<string[]>([]);
  const [copied, setCopied] = useState<string | null>(null);

  if (sorted.length === 0) {
    return (
      <div className="rounded-xl border border-dashed border-base-600 px-4 py-8 text-center">
        <div className="text-3xl">📦</div>
        <p className="mt-2 text-sm font-semibold">Link unduhan tidak tersedia</p>
        <p className="mx-auto mt-1 max-w-sm text-xs text-slate-500">
          Server sumber tidak menyediakan file unduhan untuk episode ini, atau sedang tidak aktif.
          Coba streaming di atas atau episode lain.
        </p>
      </div>
    );
  }

  const visible = sorted.filter((g) => formatFilter === 'all' || g.format === formatFilter);
  const totalLinks = visible.reduce((n, g) => n + g.links.length, 0);
  const isOpen = (key: string, idx: number) =>
    open.length === 0 ? idx === 0 : open.includes(key);

  const onCopy = async (url: string) => {
    if (await copyText(url)) {
      setCopied(url);
      window.setTimeout(() => setCopied((c) => (c === url ? null : c)), 2000);
    }
  };

  return (
    <div className="overflow-hidden rounded-xl border border-base-700/60 bg-base-800">
      <div className="flex flex-wrap items-center gap-2 border-b border-base-700/60 px-4 py-3">
        <h3 className="text-sm font-bold">⬇ {title}</h3>
        <span className="rounded-full bg-base-700 px-2 py-0.5 text-[11px] text-slate-300">
          {totalLinks} link
        </span>
        {formats.length > 1 && (
          <div className="ml-auto flex gap-1.5">
            {['all', ...formats].map((f) => (
              <button
                key={f}
                onClick={() => setFormatFilter(f)}
                className={`rounded-full px-3 py-1 text-[11px] font-semibold transition ${
                  formatFilter === f ? 'bg-accent-600 text-white' : 'bg-base-700 text-slate-300 hover:bg-base-600'
                }`}
              >
                {f === 'all' ? 'Semua' : f}
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="divide-y divide-base-700/60">
        {visible.map((g, gi) => {
          const key = `${g.format ?? ''}:${g.resolution}`;
          const expanded = isOpen(key, gi);
          return (
            <div key={key}>
              <button
                onClick={() =>
                  setOpen((prev) => (prev.includes(key) ? prev.filter((k) => k !== key) : [...prev, key]))
                }
                aria-expanded={expanded}
                className="flex w-full items-center gap-3 px-4 py-3 text-left transition hover:bg-base-700/40"
              >
                <span className="grid h-9 w-14 shrink-0 place-items-center rounded-lg bg-gradient-to-br from-accent-600 to-fuchsia-700 text-xs font-black text-white">
                  {g.resolution === 'default' ? 'SD' : g.resolution}
                </span>
                <span className="min-w-0">
                  <span className="block text-sm font-bold">
                    {g.resolution === 'default' ? 'Kualitas standar' : `Resolusi ${g.resolution}`}
                    {g.format ? ` • ${g.format}` : ''}
                  </span>
                  <span className="block text-xs text-slate-500">
                    {g.links.length} server{g.links.length > 1 ? 's' : ''}: {g.links.map((l) => l.server).join(', ')}
                  </span>
                </span>
                <span
                  className={`ml-auto shrink-0 text-slate-400 transition-transform duration-300 ${
                    expanded ? 'rotate-180' : ''
                  }`}
                >
                  ▾
                </span>
              </button>
              <div
                className={`grid transition-all duration-300 ease-in-out ${
                  expanded ? 'grid-rows-[1fr] opacity-100' : 'grid-rows-[0fr] opacity-0'
                }`}
              >
                <ul className="min-h-0 overflow-hidden">
                  {g.links.map((l: DownloadLink) => (
                    <li
                      key={l.url}
                      className="flex items-center gap-3 border-t border-base-700/40 px-4 py-2.5"
                    >
                      <span
                        className={`grid h-9 w-9 shrink-0 place-items-center rounded-lg text-sm font-black text-white ${colorFor(l.server)}`}
                      >
                        {l.server.charAt(0).toUpperCase()}
                      </span>
                      <span className="min-w-0">
                        <span className="block truncate text-sm font-semibold">{l.server}</span>
                        <span className="block truncate text-[11px] text-slate-500">
                          {safeHostname(l.url)}
                        </span>
                      </span>
                      <span className="ml-auto flex shrink-0 gap-1.5">
                        <button
                          onClick={() => onCopy(l.url)}
                          title="Salin tautan"
                          className="rounded-lg border border-base-600 px-2.5 py-1.5 text-xs font-semibold transition hover:border-accent-500 hover:text-white"
                        >
                          {copied === l.url ? '✓ Disalin' : '⧉ Salin'}
                        </button>
                        <a
                          href={l.url}
                          target="_blank"
                          rel="noreferrer"
                          className="rounded-lg bg-accent-600/20 px-3 py-1.5 text-xs font-bold text-accent-400 transition hover:bg-accent-600 hover:text-white"
                        >
                          Unduh
                        </a>
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            </div>
          );
        })}
      </div>

      <p className="border-t border-base-700/60 px-4 py-2.5 text-[11px] leading-relaxed text-slate-500">
        Bila tombol unduh tidak merespons (server tidak aktif), gunakan “Salin” lalu tempel di tab baru —
        sebagian host (Mega, Google Drive, MediaFire) wajib dibuka langsung di browser.
      </p>
    </div>
  );
}
