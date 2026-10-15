import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import { query, tx } from '../db.js';
import { config } from '../config.js';
import { HttpError } from '../lib/errors.js';
import { sendSms } from '../lib/sms.js';

const CODE_TTL_MINUTES = 5;
const CODE_RESEND_SECONDS = 60;
const MAX_ATTEMPTS = 5;

const sha256 = (text) => crypto.createHash('sha256').update(text).digest('hex');
const hashCode = (phone, code) => sha256(`${phone}:${code}:${config.jwtSecret}`);

const publicUser = (u) => ({ id: u.id, phone: u.phone, name: u.name, role: u.role });

/** Шаг 1 входа: отправить код в СМС. */
export async function requestCode(phone) {
  const { rows: recent } = await query(
    `SELECT 1 FROM auth_codes
      WHERE phone = $1 AND created_at > now() - make_interval(secs => $2)
      LIMIT 1`,
    [phone, CODE_RESEND_SECONDS],
  );
  if (recent.length > 0) {
    throw new HttpError(429, 'Код уже отправлен, подождите минуту и запросите снова');
  }

  const code =
    config.smsFixedCode ?? String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
  await query(
    `INSERT INTO auth_codes (phone, code_hash, expires_at)
     VALUES ($1, $2, now() + make_interval(mins => $3))`,
    [phone, hashCode(phone, code), CODE_TTL_MINUTES],
  );
  await sendSms(phone, `Код входа KrimFish: ${code}`);

  // Заодно чистим старое.
  await query(`DELETE FROM auth_codes WHERE expires_at < now() - interval '1 day'`);
  await query(
    `DELETE FROM refresh_tokens
      WHERE expires_at < now() - interval '1 day' OR revoked_at < now() - interval '1 day'`,
  );

  // devCode отдаётся только в режиме разработки, чтобы можно было войти без СМС.
  const exposeCode = config.smsMode === 'console' && !config.isProd;
  return { sent: true, ...(exposeCode ? { devCode: code } : {}) };
}

/** Шаг 2 входа: проверить код, создать пользователя при первом входе, выдать токены. */
export async function verifyCode(phone, code) {
  const result = await tx(async (c) => {
    const { rows } = await c.query(
      `SELECT id, code_hash AS "codeHash", attempts
         FROM auth_codes
        WHERE phone = $1 AND consumed_at IS NULL AND expires_at > now()
        ORDER BY created_at DESC, id DESC
        LIMIT 1
        FOR UPDATE`,
      [phone],
    );
    const row = rows[0];
    if (!row) return { error: new HttpError(400, 'Код истёк или не был запрошен') };
    if (row.attempts >= MAX_ATTEMPTS) {
      return { error: new HttpError(429, 'Слишком много попыток, запросите новый код') };
    }

    const given = Buffer.from(hashCode(phone, code), 'hex');
    const expected = Buffer.from(row.codeHash, 'hex');
    const ok = given.length === expected.length && crypto.timingSafeEqual(given, expected);
    if (!ok) {
      // Счётчик попыток нужно сохранить, поэтому ошибку бросаем уже после коммита.
      await c.query('UPDATE auth_codes SET attempts = attempts + 1 WHERE id = $1', [row.id]);
      return { error: new HttpError(400, 'Неверный код') };
    }
    await c.query('UPDATE auth_codes SET consumed_at = now() WHERE id = $1', [row.id]);

    const role = config.adminPhones.includes(phone) ? 'ADMIN' : 'CUSTOMER';
    const { rows: users } = await c.query(
      `INSERT INTO users (phone, role) VALUES ($1, $2)
       ON CONFLICT (phone) DO UPDATE
         SET role = CASE WHEN EXCLUDED.role = 'ADMIN' THEN 'ADMIN' ELSE users.role END
       RETURNING id, phone, name, role`,
      [phone, role],
    );
    return { user: users[0] };
  });

  if (result.error) throw result.error;
  return issueTokens(result.user);
}

async function issueTokens(user) {
  const accessToken = jwt.sign({ sub: user.id, role: user.role }, config.jwtSecret, {
    algorithm: 'HS256',
    expiresIn: config.accessTokenTtl,
  });
  const refreshToken = crypto.randomBytes(32).toString('base64url');
  await query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, now() + make_interval(days => $3))`,
    [user.id, sha256(refreshToken), config.refreshTokenTtlDays],
  );
  const { exp } = jwt.decode(accessToken);
  return {
    accessToken,
    accessTokenExpiresAt: new Date(exp * 1000).toISOString(),
    refreshToken,
    user: publicUser(user),
  };
}

/** Обмен refresh-токена на новую пару. Старый токен сразу отзывается (ротация). */
export async function refreshSession(refreshToken) {
  const { rows } = await query(
    `UPDATE refresh_tokens
        SET revoked_at = now()
      WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()
      RETURNING user_id AS "userId"`,
    [sha256(refreshToken)],
  );
  if (!rows[0]) throw new HttpError(401, 'Сессия истекла, войдите заново');

  const { rows: users } = await query(
    'SELECT id, phone, name, role FROM users WHERE id = $1 AND deleted_at IS NULL',
    [rows[0].userId],
  );
  if (!users[0]) throw new HttpError(401, 'Пользователь не найден');
  return issueTokens(users[0]);
}

export async function logout(refreshToken) {
  await query(
    'UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1 AND revoked_at IS NULL',
    [sha256(refreshToken)],
  );
}

export function verifyAccessToken(token) {
  try {
    return jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'] });
  } catch {
    throw new HttpError(401, 'Сессия истекла, войдите заново');
  }
}
