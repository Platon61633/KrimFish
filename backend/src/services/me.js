import { query, tx } from '../db.js';
import { HttpError } from '../lib/errors.js';

export async function getMe(userId) {
  const { rows } = await query(
    'SELECT id, phone, name, role, bonus FROM users WHERE id = $1 AND deleted_at IS NULL',
    [userId],
  );
  if (!rows[0]) throw new HttpError(404, 'Пользователь не найден');
  return rows[0];
}

export async function updateMe(userId, { name }) {
  await query('UPDATE users SET name = $2 WHERE id = $1', [userId, name]);
  return getMe(userId);
}

/** Удаление аккаунта (требование Apple): личные данные стираются, заказы остаются для учёта. */
export async function deleteMe(userId) {
  await tx(async (c) => {
    await c.query(
      `UPDATE users
          SET deleted_at = now(), name = NULL, phone = 'deleted:' || id::text
        WHERE id = $1`,
      [userId],
    );
    await c.query('DELETE FROM addresses WHERE user_id = $1', [userId]);
    await c.query('DELETE FROM devices WHERE user_id = $1', [userId]);
    await c.query(
      'UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
      [userId],
    );
  });
}

// ------------------------------------------------------------------ адреса

const ADDRESS_COLUMNS = 'id, line, flat, note, lat, lng';

export async function listAddresses(userId) {
  const { rows } = await query(
    `SELECT ${ADDRESS_COLUMNS} FROM addresses WHERE user_id = $1 ORDER BY created_at DESC`,
    [userId],
  );
  return rows;
}

export async function createAddress(userId, a) {
  const { rows } = await query(
    `INSERT INTO addresses (user_id, line, flat, note, lat, lng)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING ${ADDRESS_COLUMNS}`,
    [userId, a.line, a.flat ?? null, a.note ?? null, a.lat ?? null, a.lng ?? null],
  );
  return rows[0];
}

export async function updateAddress(userId, id, patch) {
  const params = [id, userId];
  const sets = [];
  for (const key of ['line', 'flat', 'note', 'lat', 'lng']) {
    if (patch[key] === undefined) continue;
    params.push(patch[key]);
    sets.push(`${key} = $${params.length}`);
  }
  if (sets.length === 0) throw new HttpError(400, 'Нет полей для изменения');
  const { rows } = await query(
    `UPDATE addresses SET ${sets.join(', ')}
      WHERE id = $1 AND user_id = $2
      RETURNING ${ADDRESS_COLUMNS}`,
    params,
  );
  if (!rows[0]) throw new HttpError(404, 'Адрес не найден');
  return rows[0];
}

export async function deleteAddress(userId, id) {
  const { rows } = await query(
    'DELETE FROM addresses WHERE id = $1 AND user_id = $2 RETURNING id',
    [id, userId],
  );
  if (!rows[0]) throw new HttpError(404, 'Адрес не найден');
}

// ------------------------------------------------------------------ устройства (push)

export async function registerDevice(userId, { token, os }) {
  await query(
    `INSERT INTO devices (user_id, token, os) VALUES ($1, $2, $3)
     ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, os = EXCLUDED.os`,
    [userId, token, os],
  );
}
