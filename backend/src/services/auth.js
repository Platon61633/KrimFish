import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import { query, tx } from '../db.js';
import { config } from '../config.js';
import { HttpError } from '../lib/errors.js';
import { verifyGoogleIdToken } from '../lib/google.js';
import { sendMail } from '../lib/mailer.js';
import { burnPasswordCheck, hashPassword, verifyPassword } from '../lib/password.js';
import { fetchVkProfile } from '../lib/vk.js';

const MAX_FAILED_LOGINS = 5;
const LOCK_MINUTES = 5;

const sha256 = (text) => crypto.createHash('sha256').update(text).digest('hex');

const USER_COLUMNS = 'id, email, phone, name, role';
const publicUser = (u) => ({
  id: u.id,
  email: u.email ?? null,
  phone: u.phone ?? null,
  name: u.name,
  role: u.role,
});

const isAdminEmail = (email) => !!email && config.adminEmails.includes(email);

/** Какие способы входа включены (для экрана входа в приложении). Ключей и секретов тут нет. */
export function authProviders() {
  return {
    password: true,
    google: config.googleClientIds.length > 0 ? { clientId: config.googleClientIds[0] } : null,
    vk: config.vk.clientId
      ? { clientId: config.vk.clientId, redirectUri: config.vk.redirectUri }
      : null,
  };
}

// ------------------------------------------------------------------ email + пароль

const CODE_TTL_MIN = 10;
const CODE_MAX_ATTEMPTS = 5;
const RESEND_SECONDS = 60;
const MAX_CODES_PER_HOUR = 5;

const codeHash = (email, code) => sha256(`${email}:${code}:${config.jwtSecret}`);
const pendingInfo = (email, devCode) => ({
  status: 'verification_required',
  email,
  resendAfter: RESEND_SECONDS,
  codeTtlMinutes: CODE_TTL_MIN,
  ...(devCode ? { devCode } : {}),
});

/** Создаёт код, прежние коды этого адреса гасит и отправляет письмо. */
async function issueEmailCode({ email, passwordHash, name }) {
  const { rows: recent } = await query(
    `SELECT count(*) FILTER (WHERE created_at > now() - interval '1 hour')::int AS hourly,
            max(created_at) > now() - make_interval(secs => $2) AS cooling
       FROM email_codes WHERE email = $1`,
    [email, RESEND_SECONDS],
  );
  if (recent[0].cooling) {
    throw new HttpError(429, `Код уже отправлен. Повторить можно через ${RESEND_SECONDS} секунд`);
  }
  if (recent[0].hourly >= MAX_CODES_PER_HOUR) {
    throw new HttpError(429, 'Слишком много писем на этот адрес. Попробуйте через час');
  }

  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
  const id = await tx(async (c) => {
    await c.query('UPDATE email_codes SET consumed_at = now() WHERE email = $1 AND consumed_at IS NULL', [email]);
    const { rows } = await c.query(
      `INSERT INTO email_codes (email, code_hash, password_hash, name, expires_at)
       VALUES ($1, $2, $3, $4, now() + make_interval(mins => $5)) RETURNING id`,
      [email, codeHash(email, code), passwordHash, name ?? null, CODE_TTL_MIN],
    );
    return rows[0].id;
  });

  try {
    await sendMail({
      to: email,
      subject: `KrimFish: код подтверждения ${code}`,
      text:
        `Ваш код подтверждения: ${code}\n\n` +
        `Он действует ${CODE_TTL_MIN} минут. Если вы не регистрировались в KrimFish, просто проигнорируйте это письмо.`,
    });
  } catch (err) {
    await query('DELETE FROM email_codes WHERE id = $1', [id]);
    throw err;
  }
  return !config.isProd && config.mail.mode === 'console' ? code : undefined;
}

export async function register({ email, password, name }) {
  if (isAdminEmail(email) && !config.adminPassword) {
    throw new HttpError(403, 'Этот адрес закреплён за администратором. Войдите через Google');
  }
  const { rows } = await query(
    'SELECT email_verified AS "verified", deleted_at AS "deletedAt" FROM users WHERE email = $1',
    [email],
  );
  if (rows[0]?.deletedAt) throw new HttpError(409, 'Этот email недоступен');
  if (rows[0]?.verified) throw new HttpError(409, 'Этот email уже зарегистрирован');

  // Аккаунт появится только после ввода кода из письма: пароль пока лежит хэшем в email_codes.
  const devCode = await issueEmailCode({ email, passwordHash: await hashPassword(password), name });
  return pendingInfo(email, devCode);
}

/** Проверяет код и создаёт (или активирует) аккаунт. */
export async function verifyEmail({ email, code }) {
  const user = await tx(async (c) => {
    const { rows } = await c.query(
      `SELECT id, code_hash AS "hash", password_hash AS "passwordHash", name, attempts
         FROM email_codes
        WHERE email = $1 AND consumed_at IS NULL AND expires_at > now()
        ORDER BY created_at DESC LIMIT 1 FOR UPDATE`,
      [email],
    );
    const row = rows[0];
    if (!row) throw new HttpError(400, 'Неверный или просроченный код');
    if (row.attempts >= CODE_MAX_ATTEMPTS) {
      throw new HttpError(429, 'Слишком много неверных попыток. Запросите новый код');
    }

    const given = Buffer.from(codeHash(email, code));
    const real = Buffer.from(row.hash);
    if (given.length !== real.length || !crypto.timingSafeEqual(given, real)) {
      // Счётчик попыток должен сохраниться, поэтому наружу выходим без исключения (иначе откат).
      await c.query('UPDATE email_codes SET attempts = attempts + 1 WHERE id = $1', [row.id]);
      return null;
    }
    await c.query('UPDATE email_codes SET consumed_at = now() WHERE id = $1', [row.id]);

    const admin = isAdminEmail(email);
    const inserted = await c.query(
        `INSERT INTO users (email, email_verified, password_hash, name, role)
         VALUES ($1, true, $2, $3, $4)
         ON CONFLICT (email) DO UPDATE
           SET email_verified = true, password_hash = EXCLUDED.password_hash,
               name = COALESCE(users.name, EXCLUDED.name),
               failed_logins = 0, locked_until = NULL
           WHERE users.email_verified = false AND users.deleted_at IS NULL
         RETURNING ${USER_COLUMNS}`,
        [email, row.passwordHash, row.name, admin ? 'ADMIN' : 'CUSTOMER'],
      );
    if (!inserted.rows[0]) throw new HttpError(409, 'Этот email уже зарегистрирован');
    return inserted.rows[0];
  });
  if (!user) throw new HttpError(400, 'Неверный код');
  // Если аккаунт был создан раньше без подтверждения, старые сессии теряют силу.
  await query('UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [user.id]);
  return issueTokens(user);
}

/** Повторная отправка кода. Ответ одинаков для любого адреса, чтобы не раскрывать, кто зарегистрирован. */
export async function resendCode({ email }) {
  const { rows: pending } = await query(
    `SELECT password_hash AS "passwordHash", name FROM email_codes
      WHERE email = $1 ORDER BY created_at DESC LIMIT 1`,
    [email],
  );
  let source = pending[0];
  if (!source) {
    const { rows } = await query(
      `SELECT password_hash AS "passwordHash", name FROM users
        WHERE email = $1 AND email_verified = false AND password_hash IS NOT NULL AND deleted_at IS NULL`,
      [email],
    );
    source = rows[0];
  }
  if (!source) return pendingInfo(email);
  const { rows: taken } = await query('SELECT 1 FROM users WHERE email = $1 AND email_verified', [email]);
  if (taken[0]) return pendingInfo(email);
  return pendingInfo(email, await issueEmailCode({ email, ...source }));
}

export async function loginWithPassword({ email, password }) {
  const { rows } = await query(
    `SELECT ${USER_COLUMNS}, password_hash AS "passwordHash", failed_logins AS "failed",
            email_verified AS "emailVerified",
            (locked_until IS NOT NULL AND locked_until > now()) AS locked
       FROM users WHERE email = $1 AND deleted_at IS NULL`,
    [email],
  );
  const user = rows[0];
  const invalid = new HttpError(401, 'Неверный email или пароль');

  if (!user) {
    await burnPasswordCheck(password);
    throw invalid;
  }
  if (user.locked) {
    throw new HttpError(429, `Слишком много попыток. Подождите ${LOCK_MINUTES} минут и повторите`);
  }
  if (!user.passwordHash) {
    throw new HttpError(401, 'Для этого email вход по паролю не настроен. Войдите через Google или VK');
  }

  if (!(await verifyPassword(password, user.passwordHash))) {
    await query(
      `UPDATE users
          SET failed_logins = failed_logins + 1,
              locked_until = CASE WHEN failed_logins + 1 >= $2
                                  THEN now() + make_interval(mins => $3) END
        WHERE id = $1`,
      [user.id, MAX_FAILED_LOGINS, LOCK_MINUTES],
    );
    throw invalid;
  }

  if (user.failed > 0) {
    await query('UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = $1', [user.id]);
  }
  if (!user.emailVerified) {
    throw new HttpError(403, 'Подтвердите почту: введите код из письма', { code: 'EMAIL_NOT_VERIFIED' });
  }
  return issueTokens(user);
}

// ------------------------------------------------------------------ Google

export async function loginWithGoogle(idToken, deps = {}) {
  const profile = await verifyGoogleIdToken(idToken, {
    audiences: config.googleClientIds,
    ...deps,
  });
  if (!profile.email || !profile.emailVerified) {
    throw new HttpError(401, 'Google не подтвердил email этого аккаунта');
  }
  const admin = isAdminEmail(profile.email);

  const user = await tx(async (c) => {
    const found = await c.query(
      `SELECT ${USER_COLUMNS}, deleted_at AS "deletedAt",
              email_verified AS "emailVerified", (password_hash IS NOT NULL) AS "hasPassword"
         FROM users
        WHERE google_sub = $1 OR email = $2
        ORDER BY (google_sub = $1) DESC NULLS LAST
        LIMIT 1 FOR UPDATE`,
      [profile.sub, profile.email],
    );
    const existing = found.rows[0];

    if (!existing) {
      const { rows } = await c.query(
        `INSERT INTO users (email, email_verified, google_sub, name, role)
         VALUES ($1, true, $2, $3, $4) RETURNING ${USER_COLUMNS}`,
        [profile.email, profile.sub, profile.name, admin ? 'ADMIN' : 'CUSTOMER'],
      );
      return rows[0];
    }
    if (existing.deletedAt) throw new HttpError(401, 'Аккаунт удалён');

    // Email подтверждён Google, поэтому аккаунт принадлежит владельцу ящика. Пароль, заданный
    // при регистрации без подтверждения почты, мог поставить кто угодно, — сбрасываем его.
    const { rows } = await c.query(
      `UPDATE users
          SET google_sub = $2,
              email = $3,
              email_verified = true,
              password_hash = CASE WHEN email_verified THEN password_hash ELSE NULL END,
              name = COALESCE(name, $4),
              role = CASE WHEN $5 THEN 'ADMIN' ELSE role END
        WHERE id = $1
        RETURNING ${USER_COLUMNS}`,
      [existing.id, profile.sub, profile.email, profile.name, admin],
    );
    if (!existing.emailVerified && existing.hasPassword) {
      await c.query(
        'UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [existing.id],
      );
    }
    return rows[0];
  });
  return issueTokens(user);
}

// ------------------------------------------------------------------ VK

export async function loginWithVk(input, deps = {}) {
  if (!config.vk.clientId) throw new HttpError(503, 'Вход через VK не настроен');
  if (input.redirectUri !== config.vk.redirectUri) {
    throw new HttpError(400, 'Неверный адрес возврата VK');
  }
  const profile = await fetchVkProfile(input, { clientId: config.vk.clientId, ...deps });

  // VK не подтверждает email так, как нам нужно для связывания аккаунтов,
  // поэтому аккаунт определяется только по vk_id и роль ADMIN через VK не выдаётся.
  const { rows } = await query(
    `INSERT INTO users (vk_id, name) VALUES ($1, $2)
     ON CONFLICT (vk_id) DO UPDATE SET name = COALESCE(users.name, EXCLUDED.name)
     RETURNING ${USER_COLUMNS}, deleted_at AS "deletedAt"`,
    [profile.id, profile.name],
  );
  if (rows[0].deletedAt) throw new HttpError(401, 'Аккаунт удалён');
  return issueTokens(rows[0]);
}

// ------------------------------------------------------------------ администраторы из .env

/**
 * При старте создаёт (или обновляет) администраторов из ADMIN_EMAILS и задаёт им пароль
 * ADMIN_PASSWORD. Так админ входит по email+паролю без регистрации «с улицы».
 */
export async function ensureAdmins() {
  if (!config.adminPassword || config.adminEmails.length === 0) return 0;
  for (const email of config.adminEmails) {
    const { rows } = await query('SELECT id, password_hash AS hash FROM users WHERE email = $1', [email]);
    const current = rows[0];
    const same = current?.hash && (await verifyPassword(config.adminPassword, current.hash));
    if (same) {
      await query("UPDATE users SET role = 'ADMIN', email_verified = true WHERE id = $1", [current.id]);
      continue;
    }
    const hash = await hashPassword(config.adminPassword);
    await query(
      `INSERT INTO users (email, email_verified, password_hash, name, role)
       VALUES ($1, true, $2, 'Администратор', 'ADMIN')
       ON CONFLICT (email) DO UPDATE
         SET role = 'ADMIN', email_verified = true, password_hash = EXCLUDED.password_hash,
             failed_logins = 0, locked_until = NULL, deleted_at = NULL`,
      [email, hash],
    );
  }
  return config.adminEmails.length;
}

// ------------------------------------------------------------------ сессии

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
  // Изредка чистим просроченные токены.
  if (crypto.randomInt(0, 20) === 0) {
    query(
      `DELETE FROM refresh_tokens
        WHERE expires_at < now() - interval '1 day' OR revoked_at < now() - interval '1 day'`,
    ).catch(() => {});
  }
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
    `SELECT ${USER_COLUMNS} FROM users WHERE id = $1 AND deleted_at IS NULL`,
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
