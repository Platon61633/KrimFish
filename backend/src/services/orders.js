import { query, tx } from '../db.js';
import { config } from '../config.js';
import { HttpError } from '../lib/errors.js';
import { discountFor, formatRub, lineTotal } from '../lib/money.js';
import { canTransition } from '../lib/status.js';
import { nowInTz } from '../lib/time.js';
import { isValidWeight } from '../lib/weight.js';
import { loadSlot } from './slots.js';

// ------------------------------------------------------------------ чтение

const ORDER_SELECT = `
  SELECT o.id, o.number, o.status, o.user_id AS "userId",
         o.slot_id AS "slotId", o.slot_date::text AS "slotDate",
         o.slot_from AS "slotFrom", o.slot_to AS "slotTo",
         o.customer_name AS "customerName", o.customer_phone AS "customerPhone",
         o.address_line AS "addressLine", o.address_note AS "addressNote",
         o.items_kop AS "itemsKop", o.discount_kop AS "discountKop",
         o.delivery_kop AS "deliveryKop", o.total_kop AS "totalKop",
         o.promo_code AS "promoCode", o.payment_status AS "paymentStatus",
         o.comment, o.created_at AS "createdAt"
    FROM orders o`;

async function withItems(db, orders) {
  if (orders.length === 0) return [];
  const { rows } = await db.query(
    `SELECT order_id AS "orderId", id, product_id AS "productId", name_snapshot AS name,
            unit, price_kop AS "priceKop", ordered_qty AS "orderedQty", actual_qty AS "actualQty"
       FROM order_items
      WHERE order_id = ANY($1::uuid[])
      ORDER BY position`,
    [orders.map((o) => o.id)],
  );
  const byOrder = new Map();
  for (const r of rows) {
    const qty = r.actualQty ?? r.orderedQty;
    const item = {
      id: r.id,
      productId: r.productId,
      name: r.name,
      unit: r.unit,
      priceKop: r.priceKop,
      orderedQty: r.orderedQty,
      actualQty: r.actualQty,
      qty,
      lineKop: lineTotal(r.unit, r.priceKop, qty),
    };
    if (!byOrder.has(r.orderId)) byOrder.set(r.orderId, []);
    byOrder.get(r.orderId).push(item);
  }
  return orders.map((o) => ({
    id: o.id,
    number: o.number,
    status: o.status,
    userId: o.userId,
    customerName: o.customerName,
    customerPhone: o.customerPhone,
    addressLine: o.addressLine,
    addressNote: o.addressNote,
    slot: { id: o.slotId, date: o.slotDate, fromHour: o.slotFrom, toHour: o.slotTo },
    items: byOrder.get(o.id) ?? [],
    itemsKop: o.itemsKop,
    discountKop: o.discountKop,
    deliveryKop: o.deliveryKop,
    totalKop: o.totalKop,
    promoCode: o.promoCode,
    paymentStatus: o.paymentStatus,
    comment: o.comment,
    createdAt: o.createdAt,
  }));
}

export async function listOrders({ userId, status, limit = 50, offset = 0 } = {}, db = { query }) {
  const params = [];
  const where = [];
  if (userId) {
    params.push(userId);
    where.push(`o.user_id = $${params.length}`);
  }
  if (status) {
    params.push(status);
    where.push(`o.status = $${params.length}`);
  }
  params.push(limit, offset);
  const sql = `${ORDER_SELECT}${where.length ? ` WHERE ${where.join(' AND ')}` : ''}
               ORDER BY o.created_at DESC, o.number DESC
               LIMIT $${params.length - 1} OFFSET $${params.length}`;
  const { rows } = await db.query(sql, params);
  return withItems(db, rows);
}

export async function getOrder(number, { userId } = {}, db = { query }) {
  const params = [number];
  let sql = `${ORDER_SELECT} WHERE o.number = $1`;
  if (userId) {
    params.push(userId);
    sql += ' AND o.user_id = $2';
  }
  const { rows } = await db.query(sql, params);
  if (!rows[0]) throw new HttpError(404, 'Заказ не найден');
  return (await withItems(db, rows))[0];
}

// ------------------------------------------------------------------ расчёт корзины

/**
 * Пересчёт корзины на сервере: данным от клиента верить нельзя.
 * С lock=true (внутри транзакции) блокирует товары, слот и промокод.
 */
export async function computeQuote(db, input, { lock = false } = {}) {
  const wanted = new Map();
  for (const it of input.items) {
    wanted.set(it.productId, (wanted.get(it.productId) ?? 0) + it.qty);
  }

  const { rows: products } = await db.query(
    `SELECT id, name, unit, price_kop AS "priceKop", stock, is_active AS "isActive"
       FROM products
      WHERE id = ANY($1::uuid[])
      ORDER BY id${lock ? ' FOR UPDATE' : ''}`,
    [[...wanted.keys()]],
  );
  const byId = new Map(products.map((p) => [p.id, p]));

  const lines = [];
  for (const [productId, qty] of wanted) {
    const p = byId.get(productId);
    if (!p || !p.isActive) throw new HttpError(400, 'Один из товаров больше недоступен');
    if (p.unit === 'kg' && !isValidWeight(qty)) {
      throw new HttpError(400, `${p.name}: вес должен быть кратен 100 г, минимум 300 г`);
    }
    if (qty > p.stock) throw new HttpError(409, `Недостаточно на складе: ${p.name}`);
    lines.push({
      productId,
      name: p.name,
      unit: p.unit,
      priceKop: p.priceKop,
      qty,
      lineKop: lineTotal(p.unit, p.priceKop, qty),
    });
  }
  const itemsKop = lines.reduce((sum, l) => sum + l.lineKop, 0);

  let slot = null;
  if (input.slotId && input.slotDate) {
    slot = await loadSlot(db, input.slotId, input.slotDate, { lock });
  }

  let promo = null;
  let discount = { percent: 0, fixedKop: 0 };
  if (input.promoCode) {
    const { rows } = await db.query(
      `SELECT id, code, percent_off AS "percentOff", amount_off_kop AS "amountOffKop",
              min_order_kop AS "minOrderKop", uses_left AS "usesLeft"
         FROM promo_codes
        WHERE code = $1 AND is_active${lock ? ' FOR UPDATE' : ''}`,
      [input.promoCode.trim().toUpperCase()],
    );
    promo = rows[0];
    if (!promo) throw new HttpError(400, 'Промокод не найден');
    if (promo.usesLeft !== null && promo.usesLeft <= 0) {
      throw new HttpError(400, 'Промокод больше не действует');
    }
    if (itemsKop < promo.minOrderKop) {
      throw new HttpError(400, `Промокод действует для заказов от ${formatRub(promo.minOrderKop)}`);
    }
    discount = { percent: promo.percentOff ?? 0, fixedKop: promo.amountOffKop ?? 0 };
  }

  const discountKop = discountFor(itemsKop, discount);
  const deliveryKop = config.deliveryKop;
  return {
    lines,
    slot,
    promo,
    discount,
    itemsKop,
    discountKop,
    deliveryKop,
    totalKop: itemsKop - discountKop + deliveryKop,
  };
}

export async function quoteCart(input, db = { query }) {
  const q = await computeQuote(db, input);
  return {
    lines: q.lines,
    promoCode: q.promo?.code ?? null,
    itemsKop: q.itemsKop,
    discountKop: q.discountKop,
    deliveryKop: q.deliveryKop,
    totalKop: q.totalKop,
  };
}

// ------------------------------------------------------------------ оформление

async function findByIdempotencyKey(userId, key) {
  const { rows } = await query(
    'SELECT number FROM orders WHERE user_id = $1 AND idempotency_key = $2',
    [userId, key],
  );
  return rows[0] ? getOrder(rows[0].number, { userId }) : null;
}

/**
 * Оформляет заказ. Возвращает { order, created }.
 * Повтор запроса с тем же Idempotency-Key возвращает уже созданный заказ (created: false).
 */
export async function placeOrder(user, input, idempotencyKey) {
  if (idempotencyKey) {
    const existing = await findByIdempotencyKey(user.id, idempotencyKey);
    if (existing) return { order: existing, created: false };
  }

  try {
    const number = await tx(async (c) => {
      const q = await computeQuote(c, input, { lock: true });
      if (!q.slot) throw new HttpError(400, 'Выберите время доставки');

      let addressLine;
      let addressNote = null;
      if (input.addressId) {
        const { rows } = await c.query(
          'SELECT line, flat, note FROM addresses WHERE id = $1 AND user_id = $2',
          [input.addressId, user.id],
        );
        if (!rows[0]) throw new HttpError(404, 'Адрес не найден');
        addressLine = rows[0].flat ? `${rows[0].line}, кв. ${rows[0].flat}` : rows[0].line;
        addressNote = rows[0].note;
      } else {
        const a = input.address;
        addressLine = a.flat ? `${a.line}, кв. ${a.flat}` : a.line;
        addressNote = a.note ?? null;
      }

      // Остаток списывается в момент оформления; товары уже заблокированы выше.
      for (const l of q.lines) {
        await c.query(
          'UPDATE products SET stock = stock - $2, updated_at = now() WHERE id = $1',
          [l.productId, l.qty],
        );
      }
      if (q.promo && q.promo.usesLeft !== null) {
        await c.query('UPDATE promo_codes SET uses_left = uses_left - 1 WHERE id = $1', [q.promo.id]);
      }

      const { rows } = await c.query(
        `INSERT INTO orders
           (user_id, slot_id, slot_date, slot_from, slot_to,
            customer_name, customer_phone, address_line, address_note,
            items_kop, discount_kop, delivery_kop, total_kop,
            promo_code, discount_percent, discount_fixed_kop, idempotency_key, comment)
         VALUES ($1, $2, $3::date, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
         RETURNING id, number`,
        [
          user.id,
          q.slot.id,
          q.slot.date,
          q.slot.fromHour,
          q.slot.toHour,
          user.name || 'Клиент',
          user.phone,
          addressLine,
          addressNote,
          q.itemsKop,
          q.discountKop,
          q.deliveryKop,
          q.totalKop,
          q.promo?.code ?? null,
          q.discount.percent,
          q.discount.fixedKop,
          idempotencyKey ?? null,
          input.comment ?? null,
        ],
      );
      const order = rows[0];

      for (let i = 0; i < q.lines.length; i++) {
        const l = q.lines[i];
        await c.query(
          `INSERT INTO order_items
             (order_id, position, product_id, name_snapshot, unit, price_kop, ordered_qty)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [order.id, i, l.productId, l.name, l.unit, l.priceKop, l.qty],
        );
      }
      return order.number;
    });
    return { order: await getOrder(number, { userId: user.id }), created: true };
  } catch (err) {
    // Два одинаковых запроса пришли одновременно: победил первый, второму отдаём его заказ.
    if (idempotencyKey && err.code === '23505' && String(err.constraint).includes('idempotency')) {
      const existing = await findByIdempotencyKey(user.id, idempotencyKey);
      if (existing) return { order: existing, created: false };
    }
    throw err;
  }
}

// ------------------------------------------------------------------ статусы

async function lockOrder(c, number, userId) {
  const params = [number];
  let sql = 'SELECT id, status, discount_percent AS "discountPercent", discount_fixed_kop AS "discountFixedKop", delivery_kop AS "deliveryKop", promo_code AS "promoCode" FROM orders WHERE number = $1';
  if (userId) {
    params.push(userId);
    sql += ' AND user_id = $2';
  }
  const { rows } = await c.query(`${sql} FOR UPDATE`, params);
  if (!rows[0]) throw new HttpError(404, 'Заказ не найден');
  return rows[0];
}

/** Возвращает на склад то, что было списано (с учётом фактического веса), и вес промокода. */
async function releaseStock(c, order) {
  await c.query(
    `UPDATE products p
        SET stock = p.stock + oi.qty, updated_at = now()
       FROM (SELECT product_id, coalesce(actual_qty, ordered_qty) AS qty
               FROM order_items WHERE order_id = $1) oi
      WHERE p.id = oi.product_id`,
    [order.id],
  );
  if (order.promoCode) {
    await c.query(
      'UPDATE promo_codes SET uses_left = uses_left + 1 WHERE code = $1 AND uses_left IS NOT NULL',
      [order.promoCode],
    );
  }
}

/** Переход статуса. Разрешены только NEW→PREPARING→ON_THE_WAY→DELIVERED и отмена из NEW/PREPARING. */
export async function transitionOrder(number, to, { userId, onlyNew = false } = {}) {
  await tx(async (c) => {
    const order = await lockOrder(c, number, userId);
    if (onlyNew && order.status !== 'NEW') {
      throw new HttpError(409, 'Клиент может отменить только новый заказ');
    }
    if (!canTransition(order.status, to)) {
      throw new HttpError(409, `Переход ${order.status} → ${to} запрещён`);
    }
    if (to === 'CANCELED') await releaseStock(c, order);
    await c.query('UPDATE orders SET status = $2, updated_at = now() WHERE id = $1', [order.id, to]);
  });
  return getOrder(number, { userId });
}

/**
 * Админ вводит фактический вес позиции при сборке. Пересчитывает итог заказа
 * и корректирует остаток на разницу.
 */
export async function setActualQty(number, itemId, actualQty) {
  await tx(async (c) => {
    const order = await lockOrder(c, number);
    if (!['NEW', 'PREPARING'].includes(order.status)) {
      throw new HttpError(409, 'Вес можно менять, пока заказ собирается');
    }
    const { rows } = await c.query(
      `SELECT id, product_id AS "productId", unit, ordered_qty AS "orderedQty", actual_qty AS "actualQty"
         FROM order_items WHERE id = $1 AND order_id = $2 FOR UPDATE`,
      [itemId, order.id],
    );
    const item = rows[0];
    if (!item) throw new HttpError(404, 'Позиция не найдена');
    if (item.unit !== 'kg') throw new HttpError(400, 'Фактический вес вводится только для весовых товаров');

    const previous = item.actualQty ?? item.orderedQty;
    // Тяжелее заказанного: берём разницу со склада; если не хватает, сработает CHECK и вернётся 409.
    await c.query(
      'UPDATE products SET stock = stock + $2, updated_at = now() WHERE id = $1',
      [item.productId, previous - actualQty],
    );
    await c.query('UPDATE order_items SET actual_qty = $2 WHERE id = $1', [item.id, actualQty]);

    const { rows: all } = await c.query(
      `SELECT unit, price_kop AS "priceKop", coalesce(actual_qty, ordered_qty) AS qty
         FROM order_items WHERE order_id = $1`,
      [order.id],
    );
    const itemsKop = all.reduce((s, r) => s + lineTotal(r.unit, r.priceKop, r.qty), 0);
    const discountKop = discountFor(itemsKop, {
      percent: order.discountPercent,
      fixedKop: order.discountFixedKop,
    });
    await c.query(
      `UPDATE orders
          SET items_kop = $2, discount_kop = $3, total_kop = $4, updated_at = now()
        WHERE id = $1`,
      [order.id, itemsKop, discountKop, itemsKop - discountKop + order.deliveryKop],
    );
  });
  return getOrder(number);
}

// ------------------------------------------------------------------ сводка

export async function dashboardStats() {
  const today = nowInTz(config.timezone).date;
  const { rows } = await query(
    `SELECT count(*) FILTER (WHERE status = 'NEW')::int AS "new",
            count(*) FILTER (WHERE status = 'PREPARING')::int AS "preparing",
            count(*) FILTER (WHERE status = 'ON_THE_WAY')::int AS "onTheWay",
            coalesce(sum(total_kop) FILTER (
              WHERE status <> 'CANCELED'
                AND (created_at AT TIME ZONE $1)::date = $2::date
            ), 0)::int AS "revenueKop"
       FROM orders`,
    [config.timezone, today],
  );
  return rows[0];
}
