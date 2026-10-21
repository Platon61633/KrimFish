import { query } from '../db.js';
import { HttpError, asyncHandler } from '../lib/errors.js';
import { verifyAccessToken } from '../services/auth.js';

/** Требует Authorization: Bearer <accessToken>. Кладёт пользователя в req.user. */
export const requireAuth = asyncHandler(async (req, _res, next) => {
  const match = /^Bearer (.+)$/.exec(req.get('authorization') ?? '');
  if (!match) throw new HttpError(401, 'Нужна авторизация');

  const payload = verifyAccessToken(match[1]);
  const { rows } = await query(
    'SELECT id, email, phone, name, role FROM users WHERE id = $1 AND deleted_at IS NULL',
    [payload.sub],
  );
  if (!rows[0]) throw new HttpError(401, 'Пользователь не найден');

  req.user = rows[0];
  next();
});

export const requireAdmin = (req, _res, next) =>
  req.user?.role === 'ADMIN' ? next() : next(new HttpError(403, 'Недостаточно прав'));
