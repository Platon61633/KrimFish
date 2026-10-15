import { Router } from 'express';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { config } from '../config.js';
import { presignPut, publicObjectUrl } from '../lib/s3.js';
import { asyncHandler } from '../lib/errors.js';
import { STATUSES } from '../lib/status.js';
import { validate } from '../lib/validate.js';
import { requireAdmin, requireAuth } from '../middleware/auth.js';
import {
  createPromo,
  createSlotTemplate,
  listPromos,
  listSlotTemplates,
  updatePromo,
  updateSlotTemplate,
} from '../services/admin.js';
import {
  changeStock,
  createCategory,
  createProduct,
  deleteProduct,
  listProducts,
  updateProduct,
} from '../services/catalog.js';
import {
  dashboardStats,
  getOrder,
  listOrders,
  setActualQty,
  transitionOrder,
} from '../services/orders.js';
import { notifyStatus } from '../services/notify.js';
import { uuid } from './catalog.js';

const router = Router();
router.use(requireAuth, requireAdmin);

const numberParam = z.object({ number: z.coerce.number().int().positive() });
const idParam = z.object({ id: uuid });

// ------------------------------------------------------------------ заказы

router.get(
  '/orders',
  validate({
    query: z.object({
      status: z.enum(STATUSES).optional(),
      limit: z.coerce.number().int().min(1).max(200).default(50),
      offset: z.coerce.number().int().min(0).default(0),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await listOrders(req.valid.query));
  }),
);

router.get(
  '/orders/:number',
  validate({ params: numberParam }),
  asyncHandler(async (req, res) => {
    res.json(await getOrder(req.valid.params.number));
  }),
);

router.post(
  '/orders/:number/transition',
  validate({ params: numberParam, body: z.object({ to: z.enum(STATUSES) }) }),
  asyncHandler(async (req, res) => {
    const order = await transitionOrder(req.valid.params.number, req.valid.body.to);
    notifyStatus(order);
    res.json(order);
  }),
);

// Фактический вес позиции после сборки: пересчитывает итог заказа.
router.patch(
  '/orders/:number/items/:itemId',
  validate({
    params: z.object({ number: z.coerce.number().int().positive(), itemId: uuid }),
    body: z.object({ actualQty: z.number().int().positive().max(1_000_000) }),
  }),
  asyncHandler(async (req, res) => {
    const { number, itemId } = req.valid.params;
    res.json(await setActualQty(number, itemId, req.valid.body.actualQty));
  }),
);

// ------------------------------------------------------------------ товары

const productFields = {
  name: z.string().trim().min(1).max(120),
  category: z.string().trim().min(1).max(60),
  unit: z.enum(['kg', 'piece', 'set']),
  priceKop: z.number().int().positive().max(100_000_000),
  stock: z.number().int().min(0).max(1_000_000_000),
  description: z.string().trim().max(2000),
  weightSteps: z.array(z.number().int().positive().max(100_000)).max(12),
  imageUrl: z.string().url().max(500).nullable(),
  isActive: z.boolean(),
};

const createProductBody = z.object({
  name: productFields.name,
  category: productFields.category,
  unit: productFields.unit,
  priceKop: productFields.priceKop,
  stock: productFields.stock,
  description: productFields.description.optional(),
  weightSteps: productFields.weightSteps.optional(),
  imageUrl: productFields.imageUrl.optional(),
  isActive: productFields.isActive.optional(),
});

router.get(
  '/products',
  asyncHandler(async (_req, res) => {
    res.json(await listProducts({ includeHidden: true }));
  }),
);

router.post(
  '/products',
  validate({ body: createProductBody }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await createProduct(req.valid.body));
  }),
);

router.patch(
  '/products/:id',
  validate({ params: idParam, body: z.object(productFields).partial() }),
  asyncHandler(async (req, res) => {
    res.json(await updateProduct(req.valid.params.id, req.valid.body));
  }),
);

router.delete(
  '/products/:id',
  validate({ params: idParam }),
  asyncHandler(async (req, res) => {
    await deleteProduct(req.valid.params.id);
    res.status(204).end();
  }),
);

router.post(
  '/products/:id/stock',
  validate({
    params: idParam,
    body: z
      .object({
        stock: z.number().int().min(0).max(1_000_000_000).optional(),
        delta: z.number().int().min(-1_000_000_000).max(1_000_000_000).optional(),
      })
      .refine((b) => (b.stock === undefined) !== (b.delta === undefined), {
        message: 'Укажите либо stock, либо delta',
      }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await changeStock(req.valid.params.id, req.valid.body));
  }),
);

router.post(
  '/categories',
  validate({
    body: z.object({
      name: z.string().trim().min(1).max(60),
      sort: z.number().int().min(0).max(1000).optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await createCategory(req.valid.body));
  }),
);

// ------------------------------------------------------------------ слоты и промокоды

const slotFields = {
  fromHour: z.number().int().min(0).max(23),
  toHour: z.number().int().min(1).max(24),
  capacity: z.number().int().min(1).max(100),
  isActive: z.boolean(),
};

router.get(
  '/slots',
  asyncHandler(async (_req, res) => {
    res.json(await listSlotTemplates());
  }),
);

router.post(
  '/slots',
  validate({
    body: z
      .object({
        fromHour: slotFields.fromHour,
        toHour: slotFields.toHour,
        capacity: slotFields.capacity.optional(),
      })
      .refine((b) => b.toHour > b.fromHour, { message: 'Конец слота позже начала', path: ['toHour'] }),
  }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await createSlotTemplate(req.valid.body));
  }),
);

router.patch(
  '/slots/:id',
  validate({ params: idParam, body: z.object(slotFields).partial() }),
  asyncHandler(async (req, res) => {
    res.json(await updateSlotTemplate(req.valid.params.id, req.valid.body));
  }),
);

const promoFields = {
  percentOff: z.number().int().min(1).max(100).nullable(),
  amountOffKop: z.number().int().positive().max(100_000_000).nullable(),
  minOrderKop: z.number().int().min(0).max(100_000_000),
  usesLeft: z.number().int().min(0).max(1_000_000).nullable(),
  isActive: z.boolean(),
};

router.get(
  '/promocodes',
  asyncHandler(async (_req, res) => {
    res.json(await listPromos());
  }),
);

router.post(
  '/promocodes',
  validate({
    body: z
      .object({
        code: z.string().trim().min(3).max(40).transform((s) => s.toUpperCase()),
        percentOff: promoFields.percentOff.optional(),
        amountOffKop: promoFields.amountOffKop.optional(),
        minOrderKop: promoFields.minOrderKop.optional(),
        usesLeft: promoFields.usesLeft.optional(),
      })
      .refine((b) => b.percentOff || b.amountOffKop, {
        message: 'Укажите percentOff или amountOffKop',
        path: ['percentOff'],
      }),
  }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await createPromo(req.valid.body));
  }),
);

router.patch(
  '/promocodes/:id',
  validate({ params: idParam, body: z.object(promoFields).partial() }),
  asyncHandler(async (req, res) => {
    res.json(await updatePromo(req.valid.params.id, req.valid.body));
  }),
);

// ------------------------------------------------------------------ сводка

router.get(
  '/stats',
  asyncHandler(async (_req, res) => {
    res.json(await dashboardStats());
  }),
);

export default router;

// --- Загрузка фото: приложение получает ссылку и кладёт файл прямо в хранилище (PUT).
const EXT = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
const uploadBody = z.object({ contentType: z.enum(['image/jpeg', 'image/png', 'image/webp']) });

router.post(
  '/uploads',
  validate({ body: uploadBody }),
  asyncHandler(async (req, res) => {
    const { contentType } = req.valid.body;
    const key = `products/${randomUUID()}.${EXT[contentType]}`;
    const { publicUrl, bucket, accessKey, secretKey, region } = config.s3;
    const expires = 600;
    res.status(201).json({
      method: 'PUT',
      uploadUrl: presignPut({ publicUrl, bucket, key, accessKey, secretKey, region, expires }),
      headers: { 'Content-Type': contentType },
      imageUrl: publicObjectUrl({ publicUrl, bucket, key }),
      expiresInSec: expires,
    });
  }),
);
