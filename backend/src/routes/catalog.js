import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../lib/errors.js';
import { validate } from '../lib/validate.js';
import { getProduct, listCategories, listProducts } from '../services/catalog.js';
import { quoteCart } from '../services/orders.js';
import { listAvailableSlots } from '../services/slots.js';

const router = Router();

export const uuid = z.string().uuid('Некорректный идентификатор');
export const dateString = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Дата в формате ГГГГ-ММ-ДД');

router.get(
  '/categories',
  asyncHandler(async (_req, res) => {
    res.json(await listCategories());
  }),
);

router.get(
  '/products',
  validate({
    query: z.object({
      category: z.string().max(60).optional(),
      q: z.string().max(100).optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await listProducts(req.valid.query));
  }),
);

router.get(
  '/products/:id',
  validate({ params: z.object({ id: uuid }) }),
  asyncHandler(async (req, res) => {
    res.json(await getProduct(req.valid.params.id));
  }),
);

router.get(
  '/slots',
  asyncHandler(async (_req, res) => {
    res.json(await listAvailableSlots());
  }),
);

export const cartItems = z
  .array(
    z.object({
      productId: uuid,
      qty: z.number().int().positive().max(1_000_000),
    }),
  )
  .min(1, 'Корзина пуста')
  .max(50);

router.post(
  '/cart/quote',
  validate({
    body: z.object({
      items: cartItems,
      slotId: uuid.optional(),
      slotDate: dateString.optional(),
      promoCode: z.string().trim().max(40).optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await quoteCart(req.valid.body));
  }),
);

export default router;
