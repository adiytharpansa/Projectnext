import { Router } from 'express';
import {
  getAnimeInfo,
  getDownloadLinks,
  getProviders,
  getWatchSources,
  searchAnime,
} from '../controllers/animeController';

const router = Router();

// GET /api/providers
router.get('/providers', getProviders);

// GET /api/anime/:provider/search?query=
router.get('/anime/:provider/search', searchAnime);

// GET /api/anime/:provider/info/:id
router.get('/anime/:provider/info/:id', getAnimeInfo);

// GET /api/anime/:provider/watch/:episodeId
router.get('/anime/:provider/watch/:episodeId', getWatchSources);

// GET /api/anime/:provider/download/:episodeId
router.get('/anime/:provider/download/:episodeId', getDownloadLinks);

export default router;
