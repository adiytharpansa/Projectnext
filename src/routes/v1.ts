import { Router } from 'express';
import {
  getProviders,
  v1AnimeInfo,
  v1DownloadLinks,
  v1SearchAnime,
  v1WatchSources,
} from '../controllers/animeController';
import { debridPoll, debridStatus, debridUnrestrict } from '../controllers/debridController';

const router = Router();

// GET /api/v1/providers
router.get('/providers', getProviders);

// GET /api/v1/anime/search?query=&provider=
router.get('/anime/search', v1SearchAnime);

// GET /api/v1/anime/info?provider=&id=
router.get('/anime/info', v1AnimeInfo);

// GET /api/v1/anime/watch?provider=&episodeId=
router.get('/anime/watch', v1WatchSources);

// GET /api/v1/anime/download?provider=&episodeId=
router.get('/anime/download', v1DownloadLinks);

// Debrid gratis (magnet → HTTP): TorBox
// GET /api/v1/debrid/status
router.get('/debrid/status', debridStatus);

// POST /api/v1/debrid/unrestrict { magnet }
router.post('/debrid/unrestrict', debridUnrestrict);

// GET /api/v1/debrid/torrent/:id
router.get('/debrid/torrent/:id', debridPoll);

export default router;
