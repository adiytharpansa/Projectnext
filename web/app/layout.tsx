import type { Metadata } from 'next';
import Navbar from '@/components/Navbar';
import './globals.css';

export const metadata: Metadata = {
  title: 'my-anime — Nonton & Unduh Anime',
  description: 'Klien streaming anime: cari, tonton (.m3u8), unduh per resolusi, dan simpan watchlist.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="id" className="dark">
      <body>
        <Navbar />
        <main className="mx-auto min-h-[calc(100vh-57px)] max-w-6xl px-4 pb-16">{children}</main>
        <footer className="border-t border-base-700/60 py-6 text-center text-xs text-slate-500">
          my-anime • ditenagai Projectnext API • gunakan dengan bijak
        </footer>
      </body>
    </html>
  );
}
