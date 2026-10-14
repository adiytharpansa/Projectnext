import Link from 'next/link';

export function LoadingState({ label = 'Memuat…' }: { label?: string }) {
  return (
    <div className="grid place-items-center py-16 text-center">
      <div className="h-10 w-10 animate-spin rounded-full border-2 border-base-600 border-t-accent-400" />
      <p className="mt-3 text-sm text-slate-400">{label}</p>
    </div>
  );
}

export function ErrorState({ message, retry }: { message: string; retry?: () => void }) {
  return (
    <div className="grid place-items-center py-16 text-center">
      <div className="text-4xl">⚠️</div>
      <p className="mt-3 max-w-md text-sm text-slate-300">{message}</p>
      {retry && (
        <button
          onClick={retry}
          className="mt-4 rounded-lg bg-accent-600 px-4 py-2 text-sm font-semibold hover:bg-accent-500"
        >
          Coba lagi
        </button>
      )}
    </div>
  );
}

export function EmptyState({ title, hint }: { title: string; hint?: string }) {
  return (
    <div className="grid place-items-center py-16 text-center">
      <div className="text-4xl">🔍</div>
      <p className="mt-3 font-semibold">{title}</p>
      {hint && <p className="mt-1 max-w-md text-sm text-slate-400">{hint}</p>}
      <Link href="/" className="mt-4 rounded-lg border border-base-600 px-4 py-2 text-sm hover:border-accent-500">
        Kembali ke beranda
      </Link>
    </div>
  );
}
