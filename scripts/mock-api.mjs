#!/usr/bin/env node
/**
 * Mock Projectnext API — kontrak identik dengan backend (`src/types.ts`,
 * envelope `{ success, status, data }`) tetapi berisi data contoh, tanpa
 * scraping. Berguna untuk mengembangkan/preview klien (web & mobile) saat
 * situs sumber tidak terjangkau.
 *
 *   node scripts/mock-api.mjs                      # :3100
 *   node scripts/mock-api.mjs --port 8080 --static mobile/build/web --assets /tmp/posters
 *
 * Opsi:
 *   --port    <n>     port (default 3100, env PORT)
 *   --static  <dir>   sajikan folder statis (mis. hasil `flutter build web`) di /
 *   --assets  <dir>   folder poster: <slug>.jpg|png; bila tak ada → PNG gradasi dibuat otomatis
 *   --delay   <ms>    latensi buatan (default 250)
 *
 * Tanpa dependensi selain Node ≥ 18.
 */
import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, resolve } from 'node:path';
import { deflateSync } from 'node:zlib';

// ───────────────────────── argumen ─────────────────────────
const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};
const PORT = Number(opt('port', process.env.PORT ?? 3100));
const STATIC_DIR = opt('static', null) ? resolve(opt('static')) : null;
const ASSETS_DIR = opt('assets', null) ? resolve(opt('assets')) : resolve('scripts/mock-assets');
const DELAY = Number(opt('delay', 250));

// ───────────────────────── katalog contoh ─────────────────────────
// Video memakai film open-license (Blender Foundation) dari bucket sampel Google.
const SAMPLE_VIDEOS = [
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
];

const PROVIDERS = [
  { id: 'gogo', name: 'Gogoanime', baseUrl: 'https://gogoanime3.net', languages: ['en'], supports: ['search', 'info', 'watch', 'download'] },
  { id: 'samehadaku', name: 'Samehadaku', baseUrl: 'https://v2.samehadaku.how', languages: ['id'], supports: ['search', 'info', 'watch', 'download'] },
  { id: 'crunchyroll', name: 'Crunchyroll', baseUrl: 'https://www.crunchyroll.com', languages: ['en', 'id'], supports: ['search', 'info'] },
  { id: 'nyaa', name: 'Nyaa.si', baseUrl: 'https://nyaa.si', languages: ['en', 'multi'], supports: ['search', 'download'] },
  { id: 'torrentio', name: 'Torrentio', baseUrl: 'https://torrentio.strem.fun', languages: ['multi'], supports: ['search', 'info', 'download'] },
  { id: 'gogoby', name: 'Gogoanime.by', baseUrl: 'https://gogoanime.by', languages: ['en'], supports: ['search', 'info', 'watch'] },
  { id: 'iqiyi', name: 'iQIYI', baseUrl: 'https://www.iq.com', languages: ['id', 'en'], supports: ['search', 'info'] },
];

const CATALOG = [
  {
    id: 'demon-slayer-kimetsu-no-yaiba', title: 'Demon Slayer: Kimetsu no Yaiba', year: 2019, type: 'TV',
    status: 'Completed', score: '8.6', episodes: 26, genres: ['Action', 'Shounen', 'Martial Arts', 'Adventure', 'Supernatural'],
    studios: ['ufotable'], otherNames: ['鬼滅の刃', 'Kimetsu no Yaiba'], colors: ['#7a1020', '#120507'],
    description: 'Tanjiro Kamado, remaja baik hati yang mencari nafkah dengan menjual arang, mendapati keluarganya dibantai iblis. Satu-satunya yang selamat, adiknya Nezuko, berubah menjadi iblis. Tanjiro bergabung dengan Korps Pembasmi Iblis demi menyembuhkan adiknya dan membalas keluarganya.',
  },
  {
    id: 'jujutsu-kaisen', title: 'Jujutsu Kaisen', year: 2020, type: 'TV',
    status: 'Ongoing', score: '8.5', episodes: 47, genres: ['Action', 'Supernatural', 'School', 'Shounen'],
    studios: ['MAPPA'], otherNames: ['呪術廻戦'], colors: ['#1b2a6b', '#07091a'],
    description: 'Yuji Itadori menelan jari Sukuna, Raja Kutukan, demi menyelamatkan teman-temannya — dan kini menampung iblis terkuat di dalam tubuhnya. Ia masuk Sekolah Tinggi Jujutsu Tokyo untuk belajar memburu kutukan.',
  },
  {
    id: 'one-piece', title: 'One Piece', year: 1999, type: 'TV',
    status: 'Ongoing', score: '8.7', episodes: 1122, genres: ['Action', 'Adventure', 'Comedy', 'Fantasy', 'Shounen'],
    studios: ['Toei Animation'], otherNames: ['ワンピース'], colors: ['#b3541e', '#1a0c05'],
    description: 'Monkey D. Luffy dan kru Topi Jerami berlayar mengarungi Grand Line demi menemukan harta karun legendaris One Piece dan menjadi Raja Bajak Laut.',
  },
  {
    id: 'attack-on-titan', title: 'Attack on Titan', year: 2013, type: 'TV',
    status: 'Completed', score: '8.9', episodes: 25, genres: ['Action', 'Drama', 'Fantasy', 'Mystery'],
    studios: ['Wit Studio', 'MAPPA'], otherNames: ['Shingeki no Kyojin', '進撃の巨人'], colors: ['#3b4a2f', '#0a0d08'],
    description: 'Umat manusia hidup di balik tembok raksasa demi berlindung dari Titan. Saat tembok terluar jebol, Eren Yeager bersumpah memusnahkan semua Titan.',
  },
  {
    id: 'spy-x-family', title: 'Spy x Family', year: 2022, type: 'TV',
    status: 'Completed', score: '8.5', episodes: 25, genres: ['Action', 'Comedy', 'Slice of Life', 'Shounen'],
    studios: ['Wit Studio', 'CloverWorks'], otherNames: ['スパイファミリー'], colors: ['#2b5f5a', '#061312'],
    description: 'Mata-mata Twilight harus membentuk keluarga palsu demi misi: istrinya ternyata pembunuh bayaran, dan putri angkatnya seorang telepat.',
  },
  {
    id: 'solo-leveling', title: 'Solo Leveling', year: 2024, type: 'TV',
    status: 'Ongoing', score: '8.4', episodes: 12, genres: ['Action', 'Adventure', 'Fantasy'],
    studios: ['A-1 Pictures'], otherNames: ['Ore dake Level Up na Ken'], colors: ['#3a1b6b', '#0a0618'],
    description: 'Sung Jinwoo, hunter terlemah di dunia, mendapat kemampuan unik untuk "naik level" tanpa batas setelah selamat dari dungeon ganda yang mematikan.',
  },
  {
    id: 'sousou-no-frieren', title: "Frieren: Beyond Journey's End", year: 2023, type: 'TV',
    status: 'Completed', score: '9.3', episodes: 28, genres: ['Adventure', 'Drama', 'Fantasy'],
    studios: ['Madhouse'], otherNames: ['Sousou no Frieren', '葬送のフリーレン'], colors: ['#1f5a7a', '#06131a'],
    description: 'Setelah mengalahkan Raja Iblis, penyihir elf Frieren memulai perjalanan baru untuk memahami manusia — dan penyesalan yang ia tinggalkan.',
  },
  {
    id: 'naruto', title: 'Naruto', year: 2002, type: 'TV',
    status: 'Completed', score: '8.0', episodes: 220, genres: ['Action', 'Adventure', 'Martial Arts', 'Shounen'],
    studios: ['Pierrot'], otherNames: ['ナルト'], colors: ['#c2581a', '#1a0a03'],
    description: 'Naruto Uzumaki, ninja muda yang menampung Rubah Ekor Sembilan, bertekad diakui desanya dan menjadi Hokage.',
  },
  {
    id: 'bleach-thousand-year-blood-war', title: 'Bleach: Thousand-Year Blood War', year: 2022, type: 'TV',
    status: 'Ongoing', score: '9.0', episodes: 13, genres: ['Action', 'Adventure', 'Supernatural'],
    studios: ['Pierrot'], otherNames: ['Bleach: Sennen Kessen-hen'], colors: ['#111111', '#4a0b0b'],
    description: 'Wandenreich menyatakan perang terhadap Soul Society. Ichigo Kurosaki kembali bertarung dalam arc terakhir Bleach.',
  },
  {
    id: 'dandadan', title: 'Dandadan', year: 2024, type: 'TV',
    status: 'Ongoing', score: '8.6', episodes: 12, genres: ['Action', 'Comedy', 'Supernatural', 'Sci-Fi'],
    studios: ['Science SARU'], otherNames: ['ダンダダン'], colors: ['#7a2b7a', '#140614'],
    description: 'Momo percaya hantu, Okarun percaya alien. Taruhan keduanya berujung pada pertemuan dengan keduanya — sekaligus.',
  },
  {
    id: 'kurokos-basketball', title: "Kuroko's Basketball", year: 2012, type: 'TV',
    status: 'Completed', score: '8.1', episodes: 25, genres: ['Sports', 'School', 'Comedy'],
    studios: ['Production I.G'], otherNames: ['Kuroko no Basket'], colors: ['#1b4d8a', '#06101d'],
    description: 'Kuroko, pemain bayangan Generasi Keajaiban, bergabung dengan SMA Seirin untuk mengalahkan mantan rekan setimnya.',
  },
];

// ───────────────────────── util ─────────────────────────
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const slugOf = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');

function episodeDate(anime, n) {
  // Episode mingguan mundur dari minggu ini (judul ongoing) / dari tahun rilis.
  const base = anime.status === 'Ongoing' ? Date.now() - (anime.episodes - n) * 7 * 864e5 : Date.UTC(anime.year, 3, 1) + (n - 1) * 7 * 864e5;
  const d = new Date(base);
  const bulan = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
  return `${d.getDate()} ${bulan[d.getMonth()]} ${d.getFullYear()}`;
}

function toSearchResult(a, provider, origin) {
  return {
    provider,
    id: a.id,
    title: a.title,
    url: `https://example.com/${provider}/${a.id}`,
    image: `${origin}/mock-assets/${a.id}.jpg`,
    releaseDate: `Released: ${a.year}`,
    type: a.type,
    score: a.score,
    genres: a.genres,
    description: a.description,
  };
}

function toInfo(a, provider, origin) {
  const total = Math.min(a.episodes, 60); // batasi agar grid tetap ringan
  const episodes = Array.from({ length: total }, (_, i) => {
    const n = i + 1;
    return {
      id: `${a.id}-episode-${n}`,
      number: n,
      title: `Episode ${n}`,
      url: `https://example.com/${provider}/${a.id}-episode-${n}`,
      ...(provider === 'samehadaku' ? { date: episodeDate(a, n) } : {}),
    };
  }).reverse(); // sumber sering membalik urutan — klien harus mengurutkan sendiri
  return {
    provider,
    id: a.id,
    title: a.title,
    url: `https://example.com/${provider}/${a.id}`,
    image: `${origin}/mock-assets/${a.id}.jpg`,
    description: a.description,
    genres: a.genres,
    status: a.status,
    type: a.type,
    releaseDate: String(a.year),
    totalEpisodes: a.episodes,
    otherNames: a.otherNames,
    score: a.score,
    studios: a.studios,
    episodes,
    batchUrl: provider === 'samehadaku' ? `https://example.com/batch/${a.id}` : null,
  };
}

function parseEpisodeId(episodeId) {
  const m = /^(.*)-episode-(\d+)$/.exec(episodeId ?? '');
  if (!m) return null;
  const anime = CATALOG.find((a) => a.id === m[1]);
  return anime ? { anime, n: Number(m[2]) } : null;
}

function downloadGroups(anime, n) {
  const mk = (res, servers, format = 'MP4') => ({
    format,
    resolution: res,
    links: servers.map((s) => ({ server: s, url: `https://example.com/dl/${anime.id}/ep${n}/${res}/${slugOf(s)}` })),
  });
  return [
    mk('1080p', ['Google Drive', 'Mega', 'Pixeldrain']),
    mk('720p', ['Google Drive', 'Mega', 'Mirrored', 'Zippyshare']),
    mk('480p', ['Google Drive', 'Mirrored']),
    mk('360p', ['Mega']),
    { format: 'MKV', resolution: '1080p', links: [{ server: 'Nyaa (magnet)', url: `magnet:?xt=urn:btih:${'0'.repeat(30)}${String(n).padStart(10, '0')}&dn=${encodeURIComponent(anime.title)}` }] },
  ];
}

function watchData(anime, n, provider, origin) {
  const video = SAMPLE_VIDEOS[(n - 1) % SAMPLE_VIDEOS.length];
  const embed = `https://example.com/embed/${anime.id}/${n}`;
  return {
    provider,
    episodeId: `${anime.id}-episode-${n}`,
    title: `${anime.title} Episode ${n}`,
    embedUrl: embed,
    headers: { Referer: embed, 'User-Agent': 'Mozilla/5.0' },
    sources: [
      { url: video, type: 'mp4', quality: '1080p', server: 'vidstream' },
      { url: video, type: 'mp4', quality: '720p', server: 'vidstream' },
      { url: video, type: 'mp4', quality: '480p', server: 'mp4upload' },
      { url: `${embed}?server=streamwish`, type: 'embed', quality: 'default', isEmbed: true, server: 'streamwish' },
    ],
    subtitles: [
      { url: `${origin}/mock-assets/sample.id.vtt`, lang: 'id', label: 'Indonesia' },
      { url: `${origin}/mock-assets/sample.en.vtt`, lang: 'en', label: 'English' },
    ],
    servers: [
      { name: 'Streamwish', url: `${embed}?server=streamwish` },
      { name: 'Doodstream', url: `${embed}?server=dood` },
    ],
    download: downloadGroups(anime, n),
  };
}

// ───────────────────────── PNG gradasi (fallback poster) ─────────────────────────
const crcTable = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, data) => {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
};
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));

function gradientPng(colors, w = 300, h = 420) {
  const [c1, c2] = colors.map(hex);
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0; // filter: none
    const t = y / (h - 1);
    for (let x = 0; x < w; x++) {
      const s = 0.85 + 0.15 * Math.sin((x / w) * Math.PI); // sedikit vignette horizontal
      const o = y * (w * 3 + 1) + 1 + x * 3;
      raw[o] = Math.round((c1[0] + (c2[0] - c1[0]) * t) * s);
      raw[o + 1] = Math.round((c1[1] + (c2[1] - c1[1]) * t) * s);
      raw[o + 2] = Math.round((c1[2] + (c2[2] - c1[2]) * t) * s);
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ───────────────────────── HTTP ─────────────────────────
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'application/javascript', '.mjs': 'application/javascript',
  '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.wasm': 'application/wasm',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff': 'font/woff', '.woff2': 'font/woff2', '.vtt': 'text/vtt',
  '.txt': 'text/plain; charset=utf-8', '.map': 'application/json', '.frag': 'text/plain', '.bin': 'application/octet-stream',
};

const SAMPLE_VTT = (lang) => `WEBVTT

00:00:00.500 --> 00:00:04.000
${lang === 'id' ? '[Subtitle contoh] Ini pratinjau Anilab dengan data tiruan.' : '[Sample subtitle] This is the Anilab preview with mock data.'}

00:00:04.500 --> 00:00:09.000
${lang === 'id' ? 'Video: film open-license dari Blender Foundation.' : 'Video: open-license films by the Blender Foundation.'}

00:00:10.000 --> 00:00:15.000
${lang === 'id' ? 'Ketuk layar untuk kontrol • CC untuk ganti subtitle.' : 'Tap the screen for controls • CC to switch subtitles.'}
`;

const json = (res, status, body) => {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(body));
};
const ok = (res, data) => json(res, 200, { success: true, status: 200, data });
const fail = (res, status, message) => json(res, status, { success: false, status, message });

function sendFile(res, path, extraHeaders = {}) {
  const st = statSync(path);
  res.writeHead(200, {
    'Content-Type': MIME[extname(path).toLowerCase()] ?? 'application/octet-stream',
    'Content-Length': st.size,
    'Access-Control-Allow-Origin': '*',
    'Cache-Control': 'public, max-age=300',
    ...extraHeaders,
  });
  createReadStream(path).pipe(res);
}

async function serveAsset(res, name) {
  const base = name.replace(/\.(jpg|jpeg|png)$/i, '');
  if (/\.vtt$/i.test(name)) {
    const lang = /\.id\.vtt$/i.test(name) ? 'id' : 'en';
    res.writeHead(200, { 'Content-Type': 'text/vtt', 'Access-Control-Allow-Origin': '*' });
    return res.end(SAMPLE_VTT(lang));
  }
  for (const ext of ['.jpg', '.jpeg', '.png']) {
    const p = join(ASSETS_DIR, base + ext);
    if (existsSync(p)) return sendFile(res, p);
  }
  const anime = CATALOG.find((a) => a.id === base);
  const png = gradientPng(anime?.colors ?? ['#333344', '#0d0d12']);
  res.writeHead(200, { 'Content-Type': 'image/png', 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'public, max-age=300' });
  res.end(png);
}

function serveStatic(req, res, pathname) {
  if (!STATIC_DIR) return false;
  const rel = normalize(decodeURIComponent(pathname)).replace(/^(\.\.[/\\])+/, '');
  let file = join(STATIC_DIR, rel);
  if (!file.startsWith(STATIC_DIR)) return false;
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, 'index.html');
  if (!existsSync(file)) {
    // SPA fallback untuk rute Flutter (go_router path URL strategy)
    file = join(STATIC_DIR, 'index.html');
    if (!existsSync(file)) return false;
  }
  sendFile(res, file, { 'Cache-Control': 'no-cache' });
  return true;
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`);
  const origin = `${req.headers['x-forwarded-proto'] ?? 'http'}://${req.headers.host ?? `localhost:${PORT}`}`;
  const q = url.searchParams;
  const p = url.pathname;

  if (req.method === 'OPTIONS') {
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS' });
    return res.end();
  }

  try {
    // ── aset ──
    if (p.startsWith('/mock-assets/')) return await serveAsset(res, p.slice('/mock-assets/'.length));

    // ── API ──
    if (p.startsWith('/api/')) {
      if (DELAY) await sleep(DELAY);

      if (p === '/api/health') return json(res, 200, { success: true, status: 200, uptime: process.uptime(), mock: true });
      if (p === '/api/providers' || p === '/api/v1/providers') return ok(res, PROVIDERS);

      if (p === '/api/v1/anime/search') {
        const query = (q.get('query') ?? '').trim();
        if (!query) return fail(res, 400, 'Parameter "query" wajib diisi. Contoh: ?query=naruto');
        const provider = (q.get('provider') ?? '').trim().toLowerCase();
        const targets = provider ? PROVIDERS.filter((x) => x.id === provider) : PROVIDERS.filter((x) => x.supports.includes('watch'));
        if (provider && targets.length === 0) return fail(res, 404, `Provider "${provider}" tidak dikenal. Tersedia: ${PROVIDERS.map((x) => x.id).join(', ')}`);
        const needle = query.toLowerCase();
        const matches = CATALOG.filter((a) => [a.title, ...a.otherNames, ...a.genres].some((t) => t.toLowerCase().includes(needle)) || needle.length <= 2);
        const results = targets.flatMap((t) => matches.map((a) => toSearchResult(a, t.id, origin)));
        const errors = provider ? [] : [{ provider: 'gogoby', message: '[Gogoanime.by] Semua mirror gagal (contoh error agregat).' }];
        return ok(res, { query, count: results.length, results, ...(errors.length ? { errors } : {}) });
      }

      if (p === '/api/v1/anime/info') {
        const id = (q.get('id') ?? '').trim();
        const provider = (q.get('provider') ?? 'gogo').trim().toLowerCase();
        const anime = CATALOG.find((a) => a.id === id);
        if (!id) return fail(res, 400, 'Parameter "id" wajib diisi');
        if (!anime) return fail(res, 404, `Anime "${id}" tidak ditemukan di ${provider}`);
        return ok(res, toInfo(anime, provider, origin));
      }

      if (p === '/api/v1/anime/watch') {
        const provider = (q.get('provider') ?? 'gogo').trim().toLowerCase();
        const parsed = parseEpisodeId(q.get('episodeId'));
        if (!parsed) return fail(res, 404, `Episode "${q.get('episodeId') ?? ''}" tidak ditemukan`);
        return ok(res, watchData(parsed.anime, parsed.n, provider, origin));
      }

      if (p === '/api/v1/anime/download') {
        const provider = (q.get('provider') ?? 'gogo').trim().toLowerCase();
        const parsed = parseEpisodeId(q.get('episodeId'));
        if (!parsed) return fail(res, 404, `Episode "${q.get('episodeId') ?? ''}" tidak ditemukan`);
        const groups = downloadGroups(parsed.anime, parsed.n);
        return ok(res, { provider, episodeId: q.get('episodeId'), count: groups.length, groups });
      }

      if (p === '/api/v1/debrid/status') {
        return ok(res, { configured: false, provider: 'torbox', plan: 'free', limits: { maxSize: '10GB per torrent', adds: '1 per 24 jam', slots: '1 aktif' }, hint: 'Mock: set TORBOX_API_KEY di backend asli' });
      }

      if (p === '/api/proxy' || p === '/api/proxy/m3u8') {
        const target = q.get('url');
        if (!target) return fail(res, 400, 'Parameter "url" wajib diisi');
        let t;
        try { t = new URL(target); } catch { return fail(res, 400, 'URL tidak valid / tidak diizinkan'); }
        // Aset lokal → sajikan langsung; lainnya → alihkan (browser mengambil sendiri).
        if (t.pathname.startsWith('/mock-assets/')) return await serveAsset(res, t.pathname.slice('/mock-assets/'.length));
        res.writeHead(302, { Location: target, 'Access-Control-Allow-Origin': '*' });
        return res.end();
      }

      return fail(res, 404, `Rute ${p} tidak ada di mock API`);
    }

    if (p === '/' && !STATIC_DIR) {
      return json(res, 200, {
        success: true, name: 'Projectnext MOCK API', mock: true,
        docs: {
          providers: 'GET /api/v1/providers',
          search: 'GET /api/v1/anime/search?query=naruto&provider=gogo',
          info: 'GET /api/v1/anime/info?provider=gogo&id=naruto',
          watch: 'GET /api/v1/anime/watch?provider=gogo&episodeId=naruto-episode-1',
          download: 'GET /api/v1/anime/download?provider=gogo&episodeId=naruto-episode-1',
        },
      });
    }

    if (serveStatic(req, res, p)) return;
    return fail(res, 404, 'Tidak ditemukan');
  } catch (e) {
    console.error(e);
    return fail(res, 500, `Mock error: ${e.message}`);
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[mock-api] http://0.0.0.0:${PORT}  static=${STATIC_DIR ?? '-'}  assets=${ASSETS_DIR}  delay=${DELAY}ms`);
});
