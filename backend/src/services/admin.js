import { query } from '../db.js';
import { HttpError } from '../lib/errors.js';

// ------------------------------------------------------------------ слоты доставки (шаблоны)

const SLOT_SELECT = `SELECT id, from_hour AS "fromHour", to_hour AS "toHour",
                            capacity, is_active AS "isActive"
                       FROM delivery_slots`;

export async function listSlotTemplates() {
  const { rows } = await query(`${SLOT_SELECT} ORDER BY from_hour`);
  return rows;
}

export async function createSlotTemplate({ fromHour, toHour, capacity }) {
  const { rows } = await query(
    `INSERT INTO delivery_slots (from_hour, to_hour, capacity) VALUES ($1, $2, $3)
     RETURNING id, from_hour AS "fromHour", to_hour AS "toHour", capacity, is_active AS "isActive"`,
    [fromHour, toHour, capacity ?? 5],
  );
  return rows[0];
}

export async function updateSlotTemplate(id, patch) {
  const params = [id];
  const sets = [];
  const columns = { fromHour: 'from_hour', toHour: 'to_hour', capacity: 'capacity', isActive: 'is_active' };
  for (const [key, column] of Object.entries(columns)) {
    if (patch[key] === undefined) continue;
    params.push(patch[key]);
    sets.push(`${column} = $${params.length}`);
  }
  if (sets.length === 0) throw new HttpError(400, 'Нет полей для изменения');
  const { rows } = await query(
    `UPDATE delivery_slots SET ${sets.join(', ')} WHERE id = $1
     RETURNING id, from_hour AS "fromHour", to_hour AS "toHour", capacity, is_active AS "isActive"`,
    params,
  );
  if (!rows[0]) throw new HttpError(404, 'Слот не найден');
  return rows[0];
}

// ------------------------------------------------------------------ промокоды

const PROMO_RETURNING = `RETURNING id, code, percent_off AS "percentOff", amount_off_kop AS "amountOffKop",
                                   min_order_kop AS "minOrderKop", uses_left AS "usesLeft", is_active AS "isActive"`;

export async function listPromos() {
  const { rows } = await query(
    `SELECT id, code, percent_off AS "percentOff", amount_off_kop AS "amountOffKop",
            min_order_kop AS "minOrderKop", uses_left AS "usesLeft", is_active AS "isActive"
       FROM promo_codes ORDER BY code`,
  );
  return rows;
}

export async function createPromo(p) {
  const { rows } = await query(
    `INSERT INTO promo_codes (code, percent_off, amount_off_kop, min_order_kop, uses_left)
     VALUES ($1, $2, $3, $4, $5) ${PROMO_RETURNING}`,
    [p.code, p.percentOff ?? null, p.amountOffKop ?? null, p.minOrderKop ?? 0, p.usesLeft ?? null],
  );
  return rows[0];
}

export async function updatePromo(id, patch) {
  const params = [id];
  const sets = [];
  const columns = {
    percentOff: 'percent_off',
    amountOffKop: 'amount_off_kop',
    minOrderKop: 'min_order_kop',
    usesLeft: 'uses_left',
    isActive: 'is_active',
  };
  for (const [key, column] of Object.entries(columns)) {
    if (patch[key] === undefined) continue;
    params.push(patch[key]);
    sets.push(`${column} = $${params.length}`);
  }
  if (sets.length === 0) throw new HttpError(400, 'Нет полей для изменения');
  const { rows } = await query(
    `UPDATE promo_codes SET ${sets.join(', ')} WHERE id = $1 ${PROMO_RETURNING}`,
    params,
  );
  if (!rows[0]) throw new HttpError(404, 'Промокод не найден');
  return rows[0];
}
