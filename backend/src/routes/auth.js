import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { HttpError, asyncHandler } from '../lib/errors.js';
import { normalizePhone } from '../lib/phone.js';
import { validate } from '../lib/validate.js';
import { logout, refreshSession, requestCode, verifyCode } from '../services/auth.js';

const router = Router();

// Защита от перебора кодов и спама СМС.
const limiter = rateLimit({
  windowMs: 60_000,
  limit: 20,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Слишком много запросов, подождите минуту' },
});
router.use(limiter);

const phoneSchema = z.string().min(5).max(30);

router.post(
  '/request-code',
  validate({ body: z.object({ phone: phoneSchema }) }),
  asyncHandler(async (req, res) => {
    const phone = normalizePhone(req.valid.body.phone);
    if (!phone) throw new HttpError(400, 'Неверный номер телефона');
    res.json(await requestCode(phone));
  }),
);

router.post(
  '/verify',
  validate({ body: z.object({ phone: phoneSchema, code: z.string().regex(/^\d{6}$/, 'Код — 6 цифр') }) }),
  asyncHandler(async (req, res) => {
    const phone = normalizePhone(req.valid.body.phone);
    if (!phone) throw new HttpError(400, 'Неверный номер телефона');
    res.json(await verifyCode(phone, req.valid.body.code));
  }),
);

const refreshBody = z.object({ refreshToken: z.string().min(20).max(200) });

router.post(
  '/refresh',
  validate({ body: refreshBody }),
  asyncHandler(async (req, res) => {
    res.json(await refreshSession(req.valid.body.refreshToken));
  }),
);

router.post(
  '/logout',
  validate({ body: refreshBody }),
  asyncHandler(async (req, res) => {
    await logout(req.valid.body.refreshToken);
    res.status(204).end();
  }),
);

export default router;
