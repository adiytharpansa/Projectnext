'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useState } from 'react';

export default function Navbar() {
  const router = useRouter();
  const pathname = usePathname();
  const [q, setQ] = useState('');

  return (
    <header className="sticky top-0 z-40 border-b border-base-700/60 bg-base-950/90 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center gap-3 px-4 py-3">
        <Link href="/" className="flex items-center gap-2">
          <span className="grid h-8 w-8 place-items-center rounded-lg bg-gradient-to-br from-accent-500 to-fuchsia-600 text-lg font-black">
            M
          </span>
          <span className="text-lg font-extrabold tracking-tight">
            my<span className="text-accent-400">-anime</span>
          </span>
        </Link>
        <form
          className="ml-auto flex w-full max-w-xs items-center gap-2 sm:max-w-sm"
          onSubmit={(e) => {
            e.preventDefault();
            if (q.trim()) router.push(`/search?q=${encodeURIComponent(q.trim())}`);
          }}
        >
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Cari anime…"
            className="h-9 w-full rounded-lg border border-base-600 bg-base-800 px-3 text-sm outline-none placeholder:text-slate-500 focus:border-accent-500"
          />
          <button
            type="submit"
            className="h-9 shrink-0 rounded-lg bg-accent-600 px-3 text-sm font-semibold hover:bg-accent-500"
          >
            Cari
          </button>
        </form>
        <nav className="hidden items-center gap-4 text-sm text-slate-300 sm:flex">
          <Link href="/" className={pathname === '/' ? 'text-white font-semibold' : 'hover:text-white'}>
            Beranda
          </Link>
        </nav>
      </div>
    </header>
  );
}
