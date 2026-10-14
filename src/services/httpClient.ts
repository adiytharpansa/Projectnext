import axios, { AxiosInstance, AxiosRequestConfig } from 'axios';
import { appConfig } from '../config';

const USER_AGENTS = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:127.0) Gecko/20100101 Firefox/127.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
];

function randomUA(): string {
  return USER_AGENTS[Math.floor(Math.random() * USER_AGENTS.length)];
}

/**
 * HTTP client terpusat: timeout, UA rotation, header Referer/Origin default.
 * Semua provider WAJIB lewat sini agar bypass proteksi konsisten.
 */
class HttpClient {
  private client: AxiosInstance;

  constructor() {
    this.client = axios.create({
      timeout: appConfig.httpTimeoutMs,
      maxRedirects: 5,
      validateStatus: (s) => s >= 200 && s < 400,
      headers: {
        'User-Agent': randomUA(),
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9,id;q=0.8',
      },
    });
  }

  /**
   * Override adapter axios (mis. 'fetch' di Cloudflare Workers).
   * Aman dipanggil kapan saja — berupa setelan, bukan perilaku default backend.
   */
  setAdapter(adapter: 'fetch' | 'http' | 'xhr'): void {
    (this.client.defaults as unknown as { adapter: unknown }).adapter = adapter;
  }

  /**
   * Override konstruktor fetch/Request/Response yang dipakai adapter
   * (axios meng-capture yang asli saat modul dimuat — perlu di-inject ulang
   * di runtime yang mem-patch global, mis. Workers).
   */
  setFetchEnv(env: { fetch: typeof fetch; Request: typeof Request; Response: typeof Response }): void {
    (this.client.defaults as unknown as { env: unknown }).env = env;
  }

  async getText(url: string, headers: Record<string, string> = {}): Promise<string> {
    const res = await this.client.get<string>(url, {
      headers: { 'User-Agent': randomUA(), ...headers },
      responseType: 'text',
    });
    return res.data;
  }

  async getJson<T = unknown>(url: string, headers: Record<string, string> = {}): Promise<T> {
    const res = await this.client.get<T>(url, {
      headers: { 'User-Agent': randomUA(), ...headers },
    });
    return res.data;
  }

  async postFormText(
    url: string,
    params: URLSearchParams | Record<string, string>,
    headers: Record<string, string> = {},
  ): Promise<string> {
    const body = params instanceof URLSearchParams ? params : new URLSearchParams(params);
    const res = await this.client.post<string>(url.toString(), body.toString(), {
      headers: {
        'User-Agent': randomUA(),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        ...headers,
      },
      responseType: 'text',
    });
    return res.data;
  }

  /** POST form-urlencoded yang mengembalikan JSON (TorBox, OAuth token, dll). */
  async postFormJson<T = unknown>(
    url: string,
    params: URLSearchParams | Record<string, string>,
    headers: Record<string, string> = {},
  ): Promise<T> {
    const body = params instanceof URLSearchParams ? params : new URLSearchParams(params);
    const res = await this.client.post<T>(url.toString(), body.toString(), {
      headers: {
        'User-Agent': randomUA(),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        Accept: 'application/json',
        ...headers,
      },
    });
    return res.data;
  }

  /** Fetch biner (image / segmen video) untuk endpoint proxy. */
  async fetchBuffer(
    url: string,
    headers: Record<string, string> = {},
    axiosConfig: AxiosRequestConfig = {},
  ) {
    return this.client.get<ArrayBuffer>(url, {
      ...axiosConfig,
      headers: { 'User-Agent': randomUA(), ...headers },
      responseType: 'arraybuffer',
    });
  }

  /** Fetch streaming langsung ke Express response (proxy). */
  async fetchStream(url: string, headers: Record<string, string> = {}) {
    return this.client.get(url, {
      headers: { 'User-Agent': randomUA(), ...headers },
      responseType: 'stream',
      timeout: 30_000,
    });
  }
}

export const httpClient = new HttpClient();
