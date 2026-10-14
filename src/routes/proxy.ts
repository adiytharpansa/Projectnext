import { Router } from 'express';
import { proxyFetch, proxyM3u8 } from '../controllers/proxyController';

const router = Router();

// GET /api/proxy?url=&referer=
router.get('/proxy', proxyFetch);

// GET /api/proxy/m3u8?url=&referer=
router.get('/proxy/m3u8', proxyM3u8);

export default router;
