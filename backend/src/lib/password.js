import crypto from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(crypto.scrypt);

// scrypt из стандартной библиотеки: без внешних зависимостей. ~32 МБ памяти на проверку.
const N = 32768;
const R = 8;
const P = 1;
const KEY_LEN = 64;
const MAXMEM = 128 * N * R * 2;

export const PASSWORD_MIN = 8;
export const PASSWORD_MAX = 128;

/** Возвращает текст ошибки или null, если пароль подходит. */
export function passwordProblem(password) {
  if (typeof password !== 'string') return 'Введите пароль';
  if (password.length < PASSWORD_MIN) return `Пароль не короче ${PASSWORD_MIN} символов`;
  if (password.length > PASSWORD_MAX) return `Пароль не длиннее ${PASSWORD_MAX} символов`;
  return null;
}

export async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const key = await scrypt(password, salt, KEY_LEN, { N, r: R, p: P, maxmem: MAXMEM });
  return ['scrypt', N, R, P, salt.toString('base64'), key.toString('base64')].join('$');
}

export async function verifyPassword(password, stored) {
  if (typeof stored !== 'string') return false;
  const [scheme, n, r, p, salt, hash] = stored.split('$');
  if (scheme !== 'scrypt' || !salt || !hash) return false;
  const expected = Buffer.from(hash, 'base64');
  const key = await scrypt(password, Buffer.from(salt, 'base64'), expected.length, {
    N: Number(n),
    r: Number(r),
    p: Number(p),
    maxmem: 128 * Number(n) * Number(r) * 2,
  });
  return key.length === expected.length && crypto.timingSafeEqual(key, expected);
}

/** Пустая проверка по заведомо чужому хэшу: время ответа не выдаёт, есть ли такой email. */
let dummy;
export async function burnPasswordCheck(password) {
  dummy ??= await hashPassword('dummy-password-for-timing');
  await verifyPassword(password, dummy);
}
