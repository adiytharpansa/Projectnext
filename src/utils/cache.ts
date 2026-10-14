/**
 * Cache in-memory sederhana (TTL) untuk mengurangi beban scraping
 * situs sumber. Key = string sembarang, value generik.
 */
interface Entry<T> {
  value: T;
  expiresAt: number;
}

export class MemoryCache {
  private store = new Map<string, Entry<unknown>>();

  constructor(private defaultTtlSeconds = 300) {}

  get<T>(key: string): T | undefined {
    const e = this.store.get(key) as Entry<T> | undefined;
    if (!e) return undefined;
    if (Date.now() > e.expiresAt) {
      this.store.delete(key);
      return undefined;
    }
    return e.value;
  }

  set<T>(key: string, value: T, ttlSeconds?: number): void {
    const ttl = (ttlSeconds ?? this.defaultTtlSeconds) * 1000;
    this.store.set(key, { value, expiresAt: Date.now() + ttl });
  }

  /** Bungkus fungsi async dengan cache. */
  async wrap<T>(key: string, fn: () => Promise<T>, ttlSeconds?: number): Promise<T> {
    const hit = this.get<T>(key);
    if (hit !== undefined) return hit;
    const value = await fn();
    this.set(key, value, ttlSeconds);
    return value;
  }

  clear(): void {
    this.store.clear();
  }
}
