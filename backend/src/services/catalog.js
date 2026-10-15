import { query, tx } from '../db.js';
import { HttpError } from '../lib/errors.js';

const PRODUCT_SELECT = `
  SELECT p.id, p.name, c.name AS category, p.unit,
         p.price_kop AS "priceKop", p.weight_steps AS "weightSteps", p.stock,
         p.description, p.image_url AS "imageUrl", p.is_active AS "isActive"
    FROM products p
    JOIN categories c ON c.id = p.category_id`;

export async function listCategories() {
  const { rows } = await query('SELECT name FROM categories ORDER BY sort, name');
  return rows.map((r) => r.name);
}

export async function createCategory({ name, sort = 0 }) {
  const { rows } = await query(
    `INSERT INTO categories (name, sort) VALUES ($1, $2)
     ON CONFLICT (name) DO UPDATE SET sort = EXCLUDED.sort
     RETURNING id, name, sort`,
    [name, sort],
  );
  return rows[0];
}

export async function listProducts({ category, q, includeHidden = false } = {}) {
  const params = [];
  const where = ['p.deleted_at IS NULL'];
  if (!includeHidden) where.push('p.is_active');
  if (category) {
    params.push(category);
    where.push(`c.name = $${params.length}`);
  }
  if (q) {
    params.push(`%${q.replace(/[\\%_]/g, '\\$&')}%`);
    where.push(`p.name ILIKE $${params.length}`);
  }
  const sql = `${PRODUCT_SELECT}${where.length ? ` WHERE ${where.join(' AND ')}` : ''}
               ORDER BY c.sort, c.name, p.name`;
  const { rows } = await query(sql, params);
  return rows;
}

export async function getProduct(id, { includeHidden = false } = {}) {
  const { rows } = await query(
    `${PRODUCT_SELECT} WHERE p.id = $1 AND p.deleted_at IS NULL${includeHidden ? '' : ' AND p.is_active'}`,
    [id],
  );
  if (!rows[0]) throw new HttpError(404, 'Товар не найден');
  return rows[0];
}

async function categoryId(db, name) {
  const { rows } = await db.query(
    `INSERT INTO categories (name) VALUES ($1)
     ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
     RETURNING id`,
    [name],
  );
  return rows[0].id;
}

export async function createProduct(data) {
  const id = await tx(async (c) => {
    const catId = await categoryId(c, data.category);
    const { rows } = await c.query(
      `INSERT INTO products
         (category_id, name, description, image_url, unit, price_kop, weight_steps, stock, is_active)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING id`,
      [
        catId,
        data.name,
        data.description ?? '',
        data.imageUrl ?? null,
        data.unit,
        data.priceKop,
        data.weightSteps ?? (data.unit === 'kg' ? [300, 500, 1000] : []),
        data.stock,
        data.isActive ?? false, // новый товар скрыт, пока админ не включит показ
      ],
    );
    return rows[0].id;
  });
  return getProduct(id, { includeHidden: true });
}

const PATCH_COLUMNS = {
  name: 'name',
  description: 'description',
  imageUrl: 'image_url',
  unit: 'unit',
  priceKop: 'price_kop',
  weightSteps: 'weight_steps',
  stock: 'stock',
  isActive: 'is_active',
};

export async function updateProduct(id, patch) {
  await tx(async (c) => {
    const params = [id];
    const sets = [];
    for (const [key, column] of Object.entries(PATCH_COLUMNS)) {
      if (patch[key] === undefined) continue;
      params.push(patch[key]);
      sets.push(`${column} = $${params.length}`);
    }
    if (patch.category !== undefined) {
      params.push(await categoryId(c, patch.category));
      sets.push(`category_id = $${params.length}`);
    }
    if (sets.length === 0) throw new HttpError(400, 'Нет полей для изменения');
    const { rows } = await c.query(
      `UPDATE products SET ${sets.join(', ')}, updated_at = now() WHERE id = $1 AND deleted_at IS NULL RETURNING id`,
      params,
    );
    if (!rows[0]) throw new HttpError(404, 'Товар не найден');
  });
  return getProduct(id, { includeHidden: true });
}

/**
 * Удаление товара. Товар скрывается и больше не продаётся, но остаётся в базе,
 * чтобы старые заказы сохранили названия и цены.
 */
export async function deleteProduct(id) {
  const { rows } = await query(
    `UPDATE products SET deleted_at = now(), is_active = false, updated_at = now()
      WHERE id = $1 AND deleted_at IS NULL RETURNING id`,
    [id],
  );
  if (!rows[0]) throw new HttpError(404, 'Товар не найден');
}

/** Быстрое обновление остатка: абсолютное значение (stock) или изменение (delta). */
export async function changeStock(id, { stock, delta }) {
  const { rows } =
    stock !== undefined
      ? await query(
          'UPDATE products SET stock = $2, updated_at = now() WHERE id = $1 RETURNING id',
          [id, stock],
        )
      : await query(
          'UPDATE products SET stock = stock + $2, updated_at = now() WHERE id = $1 RETURNING id',
          [id, delta],
        );
  if (!rows[0]) throw new HttpError(404, 'Товар не найден');
  return getProduct(id, { includeHidden: true });
}
