import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import { config } from './config.js';
import { query } from './db.js';
import { HttpError, asyncHandler } from './lib/errors.js';
import adminRoutes from './routes/admin.js';
import authRoutes from './routes/auth.js';
import catalogRoutes from './routes/catalog.js';
import meRoutes from './routes/me.js';
import orderRoutes from './routes/orders.js';

/** Короткий лог запросов: метод, путь, код ответа, время. */
function requestLogger(req, res, next) {
  const started = Date.now();
  res.on('finish', () => {
    if (req.path === '/health') return;
    console.log(`${req.method} ${req.originalUrl.split('?')[0]} ${res.statusCode} ${Date.now() - started}ms`);
  });
  next();
}

/** Переводит ошибки базы данных в понятные ответы. */
function describeDbError(err) {
  switch (err.code) {
    case '23505':
      return new HttpError(409, 'Такая запись уже существует');
    case '23503':
      return new HttpError(409, 'Связанная запись не найдена или используется');
    case '23514':
      return String(err.constraint).includes('stock')
        ? new HttpError(409, 'Недостаточно товара на складе')
        : new HttpError(409, 'Значение не проходит проверку');
    case '22P02':
    case '22007':
    case '22003':
      return new HttpError(400, 'Некорректный формат данных');
    default:
      return null;
  }
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, _req, res, _next) {
  if (err?.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'Некорректный JSON' });
  }
  if (err?.type === 'entity.too.large') {
    return res.status(413).json({ error: 'Слишком большой запрос' });
  }
  const mapped = err instanceof HttpError ? err : describeDbError(err);
  if (mapped) {
    return res
      .status(mapped.status)
      .json({ error: mapped.message, ...(mapped.details ? { details: mapped.details } : {}) });
  }
  console.error(err);
  res.status(500).json({ error: 'Внутренняя ошибка сервера' });
}

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  if (config.trustProxy) app.set('trust proxy', config.trustProxy);

  app.use(helmet());
  app.use(
    cors({
      origin: config.corsOrigin === '*' ? '*' : config.corsOrigin.split(',').map((s) => s.trim()),
      methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key'],
    }),
  );
  app.use(express.json({ limit: '100kb' }));
  app.use(requestLogger);

  app.get(
    '/health',
    asyncHandler(async (_req, res) => {
      try {
        await query('SELECT 1');
        res.json({ ok: true, time: new Date().toISOString() });
      } catch {
        res.status(503).json({ ok: false, error: 'База данных недоступна' });
      }
    }),
  );

  app.use(catalogRoutes);
  app.use('/auth', authRoutes);
  app.use(meRoutes);
  app.use(orderRoutes);
  app.use('/admin', adminRoutes);

  app.use((_req, _res, next) => next(new HttpError(404, 'Маршрут не найден')));
  app.use(errorHandler);
  return app;
}
