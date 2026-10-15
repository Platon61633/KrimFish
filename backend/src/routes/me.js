import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../lib/errors.js';
import { validate } from '../lib/validate.js';
import { requireAuth } from '../middleware/auth.js';
import {
  createAddress,
  deleteAddress,
  deleteMe,
  getMe,
  listAddresses,
  registerDevice,
  updateAddress,
  updateMe,
} from '../services/me.js';
import { uuid } from './catalog.js';

const router = Router();
router.use('/me', requireAuth);

router.get(
  '/me',
  asyncHandler(async (req, res) => {
    res.json(await getMe(req.user.id));
  }),
);

router.patch(
  '/me',
  validate({ body: z.object({ name: z.string().trim().min(1).max(80) }) }),
  asyncHandler(async (req, res) => {
    res.json(await updateMe(req.user.id, req.valid.body));
  }),
);

router.delete(
  '/me',
  asyncHandler(async (req, res) => {
    await deleteMe(req.user.id);
    res.status(204).end();
  }),
);

const addressFields = {
  line: z.string().trim().min(3).max(200),
  flat: z.string().trim().max(20).nullable().optional(),
  note: z.string().trim().max(300).nullable().optional(),
  lat: z.number().min(-90).max(90).nullable().optional(),
  lng: z.number().min(-180).max(180).nullable().optional(),
};

router.get(
  '/me/addresses',
  asyncHandler(async (req, res) => {
    res.json(await listAddresses(req.user.id));
  }),
);

router.post(
  '/me/addresses',
  validate({ body: z.object(addressFields) }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await createAddress(req.user.id, req.valid.body));
  }),
);

router.patch(
  '/me/addresses/:id',
  validate({
    params: z.object({ id: uuid }),
    body: z.object(addressFields).partial(),
  }),
  asyncHandler(async (req, res) => {
    res.json(await updateAddress(req.user.id, req.valid.params.id, req.valid.body));
  }),
);

router.delete(
  '/me/addresses/:id',
  validate({ params: z.object({ id: uuid }) }),
  asyncHandler(async (req, res) => {
    await deleteAddress(req.user.id, req.valid.params.id);
    res.status(204).end();
  }),
);

router.post(
  '/me/devices',
  validate({
    body: z.object({
      token: z.string().min(10).max(500),
      os: z.enum(['android', 'ios', 'web']),
    }),
  }),
  asyncHandler(async (req, res) => {
    await registerDevice(req.user.id, req.valid.body);
    res.status(204).end();
  }),
);

export default router;
