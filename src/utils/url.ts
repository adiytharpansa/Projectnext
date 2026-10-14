/** Helper URL kecil. */

/** Gabung base + path tanpa double slash. */
export function joinUrl(base: string, path: string): string {
  if (/^https?:\/\//i.test(path)) return path;
  if (path.startsWith('//')) return `https:${path}`;
  return `${base.replace(/\/$/, '')}/${path.replace(/^\//, '')}`;
}

/** Normalisasi URL protokol-relatif (//...) atau root-relatif. */
export function normalizeUrl(base: string, raw?: string): string {
  if (!raw) return '';
  const u = raw.trim();
  if (!u) return '';
  if (/^https?:\/\//i.test(u)) return u;
  if (u.startsWith('//')) return `https:${u}`;
  return joinUrl(base, u);
}

/** Ambil slug terakhir dari URL/path. */
export function slugFromUrl(url: string): string {
  try {
    const clean = url.split('?')[0].split('#')[0].replace(/\/$/, '');
    return decodeURIComponent(clean.split('/').pop() ?? clean);
  } catch {
    return url;
  }
}

/** Validasi http(s) URL untuk endpoint proxy (cegah SSRF ke host internal). */
export function isAllowedProxyUrl(raw: string): boolean {
  try {
    const u = new URL(raw);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return false;
    const host = u.hostname.toLowerCase();
    const blocked = ['localhost', '127.0.0.1', '0.0.0.0', '::1', '169.254.169.254'];
    if (blocked.includes(host)) return false;
    if (host.endsWith('.internal') || host.endsWith('.local')) return false;
    return true;
  } catch {
    return false;
  }
}

/** Resolve URL relatif terhadap playlist m3u8. */
export function resolveM3u8Url(playlistUrl: string, line: string): string {
  if (/^https?:\/\//i.test(line)) return line;
  try {
    return new URL(line, playlistUrl).toString();
  } catch {
    return line;
  }
}
