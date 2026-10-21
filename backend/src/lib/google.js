import crypto from 'node:crypto';
import { HttpError } from './errors.js';

const CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const ISSUERS = ['https://accounts.google.com', 'accounts.google.com'];

let cache = { keys: null, expiresAt: 0 };

/** Публичные ключи Google (JWKS) с кэшем по заголовку Cache-Control. */
export async function loadGoogleKeys({ force = false, fetchImpl = fetch } = {}) {
  if (!force && cache.keys && Date.now() < cache.expiresAt) return cache.keys;
  const res = await fetchImpl(CERTS_URL, { signal: AbortSignal.timeout(10_000) });
  if (!res.ok) throw new HttpError(502, 'Не удалось связаться с Google, попробуйте позже');
  const body = await res.json();
  const maxAge = /max-age=(\d+)/.exec(res.headers.get('cache-control') ?? '')?.[1];
  cache = {
    keys: body.keys ?? [],
    expiresAt: Date.now() + (maxAge ? Number(maxAge) * 1000 : 3_600_000),
  };
  return cache.keys;
}

const bad = () => new HttpError(401, 'Не удалось проверить вход через Google');
const b64json = (part) => JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));

/**
 * Проверяет idToken, выданный Google: подпись RS256, издателя, получателя (наш client ID) и срок.
 * Возвращает { sub, email, emailVerified, name }.
 */
export async function verifyGoogleIdToken(
  idToken,
  { audiences, getKeys = loadGoogleKeys, nowMs = Date.now() },
) {
  if (!audiences?.length) throw new HttpError(503, 'Вход через Google не настроен');
  const parts = typeof idToken === 'string' ? idToken.split('.') : [];
  if (parts.length !== 3) throw bad();

  let header;
  let payload;
  try {
    header = b64json(parts[0]);
    payload = b64json(parts[1]);
  } catch {
    throw bad();
  }
  if (header.alg !== 'RS256' || !header.kid) throw bad();

  let jwk = (await getKeys()).find((k) => k.kid === header.kid);
  if (!jwk) jwk = (await getKeys({ force: true })).find((k) => k.kid === header.kid);
  if (!jwk) throw bad();

  const signed = Buffer.from(`${parts[0]}.${parts[1]}`);
  const signature = Buffer.from(parts[2], 'base64url');
  let valid = false;
  try {
    const key = crypto.createPublicKey({ key: jwk, format: 'jwk' });
    valid = crypto.verify('RSA-SHA256', signed, key, signature);
  } catch {
    valid = false;
  }
  if (!valid) throw bad();

  const nowSec = Math.floor(nowMs / 1000);
  if (!ISSUERS.includes(payload.iss)) throw bad();
  if (!audiences.includes(payload.aud)) throw bad();
  if (typeof payload.exp !== 'number' || payload.exp <= nowSec) throw bad();
  if (typeof payload.sub !== 'string' || !payload.sub) throw bad();

  return {
    sub: payload.sub,
    email: typeof payload.email === 'string' ? payload.email.toLowerCase() : null,
    emailVerified: payload.email_verified === true || payload.email_verified === 'true',
    name: typeof payload.name === 'string' ? payload.name : null,
  };
}
