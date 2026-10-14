/**
 * Kontrak resolver debrid: magnet → link HTTP yang bisa di-stream.
 * Implementasi saat ini: TorBox (paket GRATIS: maks 10GB/torrent,
 * 1 unduhan per 24 jam, 10 per bulan; file cached tidak memakan slot).
 */
export type DebridState = 'ready' | 'pending' | 'downloading';

export interface DebridFile {
  id: number;
  name: string;
  size: number;
}

export interface UnrestrictResult {
  state: DebridState;
  /** ID internal untuk polling bila belum siap. */
  torrentId?: number;
  /** Link HTTP langsung bila sudah siap. */
  streamUrl?: string;
  file?: DebridFile;
  progress?: number;
  /** Pesan ramah untuk UI (mis. batas paket gratis). */
  note?: string;
}

export interface DebridResolver {
  readonly name: string;
  isConfigured(): boolean;
  /** Magnet → siap (cached) atau antrean unduhan. */
  unrestrict(magnet: string): Promise<UnrestrictResult>;
  /** Refresh status unduhan yang tertunda. */
  poll(torrentId: number): Promise<UnrestrictResult>;
}
