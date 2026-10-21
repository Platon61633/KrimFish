import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../lib/errors.js';
import { validate } from '../lib/validate.js';
import { requireAuth } from '../middleware/auth.js';
import { notifyClientCanceled, notifyNewOrder } from '../services/notify.js';
import { getOrder, listOrders, placeOrder, transitionOrder } from '../services/orders.js';
import { cartItems, dateString, uuid } from './catalog.js';

const router = Router();
router.use('/orders', requireAuth);

const numberParam = z.object({ number: z.coerce.number().int().positive() });

const createOrderBody = z
  .object({
    items: cartItems,
    slotId: uuid,
    slotDate: dateString,
    promoCode: z.string().trim().max(40).optional(),
    addressId: uuid.optional(),
    address: z
      .object({
        line: z.string().trim().min(3).max(200),
        flat: z.string().trim().max(20).optional(),
        note: z.string().trim().max(300).optional(),
      })
      .optional(),
    comment: z.string().trim().max(500).optional(),
    // Телефон для связи с курьером; обязателен, если его ещё нет в профиле.
    phone: z.string().trim().min(5).max(30).optional(),
  })
  .refine((b) => b.addressId || b.address, {
    message: 'Укажите адрес доставки',
    path: ['address'],
  });

router.post(
  '/orders',
  validate({
    body: createOrderBody,
  }),
  asyncHandler(async (req, res) => {
    const key = req.get('idempotency-key')?.slice(0, 100);
    const { order, created } = await placeOrder(req.user, req.valid.body, key);
    if (created) notifyNewOrder(order);
    res.status(created ? 201 : 200).json(order);
  }),
);

router.get(
  '/orders',
  validate({
    query: z.object({
      limit: z.coerce.number().int().min(1).max(100).default(50),
      offset: z.coerce.number().int().min(0).default(0),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await listOrders({ userId: req.user.id, ...req.valid.query }));
  }),
);

router.get(
  '/orders/:number',
  validate({ params: numberParam }),
  asyncHandler(async (req, res) => {
    res.json(await getOrder(req.valid.params.number, { userId: req.user.id }));
  }),
);

router.post(
  '/orders/:number/cancel',
  validate({ params: numberParam }),
  asyncHandler(async (req, res) => {
    const order = await transitionOrder(req.valid.params.number, 'CANCELED', {
      userId: req.user.id,
      onlyNew: true,
    });
    notifyClientCanceled(order);
    res.json(order);
  }),
);

export default router;
