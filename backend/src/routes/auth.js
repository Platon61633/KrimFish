import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { HttpError, asyncHandler } from '../lib/errors.js';
import { normalizeEmail } from '../lib/email.js';
import { passwordProblem } from '../lib/password.js';
import { validate } from '../lib/validate.js';
import {
  authProviders,
  loginWithGoogle,
  loginWithPassword,
  loginWithVk,
  logout,
  refreshSession,
  register,
  resendCode,
  verifyEmail,
} from '../services/auth.js';

const router = Router();

const message = (error) => ({ error });
const common = {
  standardHeaders: 'draft-7',
  legacyHeaders: false,
};

// Общий лимит и отдельный, более строгий — на вход и регистрацию (защита от перебора паролей).
router.use(
  rateLimit({ ...common, windowMs: 60_000, limit: 60, message: message('Слишком много запросов, подождите минуту') }),
);
const credentialsLimiter = rateLimit({
  ...common,
  windowMs: 60_000,
  limit: 10,
  message: message('Слишком много попыток входа, подождите минуту'),
});

const emailField = z.string().max(254).transform((v, ctx) => {
  const email = normalizeEmail(v);
  if (!email) ctx.addIssue({ code: 'custom', message: 'Неверный email' });
  return email;
});

const passwordField = z.string().max(128).superRefine((v, ctx) => {
  const problem = passwordProblem(v);
  if (problem) ctx.addIssue({ code: 'custom', message: problem });
});

router.get('/providers', (_req, res) => {
  res.json(authProviders());
});

router.post(
  '/register',
  credentialsLimiter,
  validate({
    body: z.object({
      email: emailField,
      password: passwordField,
      name: z.string().trim().min(1).max(80).optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.status(202).json(await register(req.valid.body));
  }),
);

router.post(
  '/verify-email',
  credentialsLimiter,
  validate({ body: z.object({ email: emailField, code: z.string().regex(/^\d{6}$/, 'Код — 6 цифр') }) }),
  asyncHandler(async (req, res) => {
    res.json(await verifyEmail(req.valid.body));
  }),
);

router.post(
  '/resend-code',
  credentialsLimiter,
  validate({ body: z.object({ email: emailField }) }),
  asyncHandler(async (req, res) => {
    res.json(await resendCode(req.valid.body));
  }),
);

router.post(
  '/login',
  credentialsLimiter,
  validate({
    body: z.object({
      email: emailField,
      // Для входа длину не проверяем: у старых аккаунтов правила могли быть другими.
      password: z.string().min(1).max(128),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await loginWithPassword(req.valid.body));
  }),
);

router.post(
  '/google',
  credentialsLimiter,
  validate({ body: z.object({ idToken: z.string().min(20).max(4096) }) }),
  asyncHandler(async (req, res) => {
    res.json(await loginWithGoogle(req.valid.body.idToken));
  }),
);

router.post(
  '/vk',
  credentialsLimiter,
  validate({
    body: z.object({
      code: z.string().min(1).max(2000),
      codeVerifier: z.string().min(43).max(128),
      deviceId: z.string().min(1).max(200),
      redirectUri: z.string().min(1).max(300),
      state: z.string().min(1).max(200),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await loginWithVk(req.valid.body));
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
