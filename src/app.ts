import 'dotenv/config'; // fallback bila app dipakai tanpa via index.ts (Vercel memakai env platform)
import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';
import animeRoutes from './routes/anime';
import proxyRoutes from './routes/proxy';
import v1Routes from './routes/v1';
import { errorMiddleware, notFoundMiddleware } from './middlewares/errorHandler';
import { appConfig } from './config';

export function createApp(): express.Express {
  const app = express();

  app.use(
    cors({
      origin: appConfig.corsOrigin === '*' ? '*' : appConfig.corsOrigin.split(','),
    }),
  );
  app.use(express.json({ limit: '1mb' }));
  app.use(morgan(appConfig.nodeEnv === 'production' ? 'combined' : 'dev'));

  app.use(
    '/api/',
    rateLimit({
      windowMs: appConfig.rateWindowMs,
      max: appConfig.rateMax,
      standardHeaders: true,
      legacyHeaders: false,
      message: { success: false, status: 429, message: 'Terlalu banyak request, coba lagi nanti' },
    }),
  );

  // Landing
  app.get('/', (_req, res) => {
    res.json({
      success: true,
      name: 'Projectnext',
      description: 'Modular anime scraper API (ala Consumet) — Gogoanime & Samehadaku',
      version: '1.0.0',
      docs: {
        providers: 'GET /api/providers',
        search: 'GET /api/anime/:provider/search?query=naruto',
        info: 'GET /api/anime/:provider/info/:id',
        watch: 'GET /api/anime/:provider/watch/:episodeId',
        download: 'GET /api/anime/:provider/download/:episodeId',
        v1Search: 'GET /api/v1/anime/search?query=naruto&provider=gogo',
        v1Info: 'GET /api/v1/anime/info?provider=gogo&id=naruto',
        v1Watch: 'GET /api/v1/anime/watch?provider=gogo&episodeId=naruto-episode-10',
        v1Download: 'GET /api/v1/anime/download?provider=gogo&episodeId=naruto-episode-10',
        proxy: 'GET /api/proxy?url=<encoded>&referer=<encoded>',
        proxyM3u8: 'GET /api/proxy/m3u8?url=<encoded>&referer=<encoded>',
        health: 'GET /api/health',
      },
      providers: ['gogo', 'samehadaku'],
      note: 'Ganti domain sumber via env GOGO_BASE_URL / GOGO_AJAX_URL / SAMEHADAKU_BASE_URL',
    });
  });

  app.get('/api/health', (_req, res) => {
    res.json({ success: true, status: 200, uptime: process.uptime() });
  });

  app.use('/api', animeRoutes);
  app.use('/api', proxyRoutes);
  app.use('/api/v1', v1Routes);

  app.use(notFoundMiddleware);
  app.use(errorMiddleware);

  return app;
}
