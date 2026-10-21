import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { test } from 'node:test';
import { normalizeEmail } from '../src/lib/email.js';
import { verifyGoogleIdToken } from '../src/lib/google.js';
import { hashPassword, passwordProblem, verifyPassword } from '../src/lib/password.js';
import { fetchVkProfile } from '../src/lib/vk.js';

test('email: нижний регистр и проверка формата', () => {
  assert.equal(normalizeEmail('  Ivan@Mail.RU '), 'ivan@mail.ru');
  for (const bad of ['', 'ivan', 'ivan@', '@mail.ru', 'iv an@mail.ru', 'a@b', null, 5]) {
    assert.equal(normalizeEmail(bad), null, String(bad));
  }
});

test('пароль: длина от 8 до 128', () => {
  assert.equal(passwordProblem('12345678'), null);
  assert.match(passwordProblem('1234567'), /не короче 8/);
  assert.match(passwordProblem('x'.repeat(129)), /не длиннее 128/);
});

test('пароль: хэш проверяется, чужой пароль и мусор не проходят', async () => {
  const hash = await hashPassword('correct horse');
  assert.match(hash, /^scrypt\$/);
  assert.equal(await verifyPassword('correct horse', hash), true);
  assert.equal(await verifyPassword('correct horsf', hash), false);
  assert.equal(await verifyPassword('x', 'не-хэш'), false);
  assert.equal(await verifyPassword('x', null), false);
  // Соль разная: хэши одного пароля не совпадают.
  assert.notEqual(hash, await hashPassword('correct horse'));
});

// ------------------------------------------------------------------ Google

const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'test-kid', alg: 'RS256', use: 'sig' };
const AUD = ['web-client-id.apps.googleusercontent.com'];
const NOW = 1_800_000_000_000;

function makeToken(overrides = {}, { key = privateKey, kid = 'test-kid', alg = 'RS256' } = {}) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const payload = {
    iss: 'https://accounts.google.com',
    aud: AUD[0],
    sub: '1234567890',
    email: 'Ivan@Gmail.com',
    email_verified: true,
    name: 'Иван Петров',
    exp: NOW / 1000 + 3600,
    ...overrides,
  };
  const head = `${b64({ alg, kid, typ: 'JWT' })}.${b64(payload)}`;
  const sig = crypto.sign('RSA-SHA256', Buffer.from(head), key).toString('base64url');
  return `${head}.${sig}`;
}

const opts = { audiences: AUD, getKeys: async () => [jwk], nowMs: NOW };

test('Google: корректный токен разбирается', async () => {
  const p = await verifyGoogleIdToken(makeToken(), opts);
  assert.deepEqual(p, {
    sub: '1234567890',
    email: 'ivan@gmail.com',
    emailVerified: true,
    name: 'Иван Петров',
  });
});

test('Google: чужая подпись, срок, получатель и издатель отклоняются', async () => {
  const other = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey;
  const cases = [
    makeToken({}, { key: other }),
    makeToken({ exp: NOW / 1000 - 1 }),
    makeToken({ aud: 'чужое-приложение' }),
    makeToken({ iss: 'https://evil.example' }),
    makeToken({}, { kid: 'unknown-kid' }),
    makeToken({}, { alg: 'none' }),
    'a.b',
    'мусор',
    '',
  ];
  for (const t of cases) {
    await assert.rejects(() => verifyGoogleIdToken(t, opts), { status: 401 });
  }
});

test('Google: подмена содержимого после подписи отклоняется', async () => {
  const [h, , s] = makeToken().split('.');
  const forged = Buffer.from(
    JSON.stringify({ iss: 'accounts.google.com', aud: AUD[0], sub: 'victim', exp: NOW / 1000 + 99 }),
  ).toString('base64url');
  await assert.rejects(() => verifyGoogleIdToken(`${h}.${forged}.${s}`, opts), { status: 401 });
});

test('Google: без настроенного client ID вход выключен', async () => {
  await assert.rejects(() => verifyGoogleIdToken(makeToken(), { ...opts, audiences: [] }), {
    status: 503,
  });
});

test('Google: email_verified строкой "true" принимается, "false" нет', async () => {
  assert.equal((await verifyGoogleIdToken(makeToken({ email_verified: 'true' }), opts)).emailVerified, true);
  assert.equal((await verifyGoogleIdToken(makeToken({ email_verified: 'false' }), opts)).emailVerified, false);
});

// ------------------------------------------------------------------ VK

function vkFetch(calls, { auth, info }) {
  return async (url, init) => {
    calls.push({ url, body: Object.fromEntries(init.body) });
    const reply = url.endsWith('/auth') ? auth : info;
    return { ok: !reply.error, status: reply.error ? 400 : 200, json: async () => reply };
  };
}

test('VK: код меняется на токен, профиль возвращается', async () => {
  const calls = [];
  const fetchImpl = vkFetch(calls, {
    auth: { access_token: 'tok', user_id: 77 },
    info: { user: { user_id: '77', first_name: 'Анна', last_name: 'Иванова' } },
  });
  const p = await fetchVkProfile(
    { code: 'c', codeVerifier: 'v'.repeat(43), deviceId: 'd', redirectUri: 'vk1://vk.ru/blank.html', state: 's' },
    { clientId: '1', fetchImpl },
  );
  assert.deepEqual(p, { id: '77', name: 'Анна Иванова' });
  assert.equal(calls[0].body.grant_type, 'authorization_code');
  assert.equal(calls[0].body.client_id, '1');
  assert.equal(calls[0].body.code_verifier, 'v'.repeat(43));
  assert.equal(calls[1].body.access_token, 'tok');
});

test('VK: ошибка провайдера даёт 401', async () => {
  const fetchImpl = vkFetch([], { auth: { error: 'invalid_grant' }, info: {} });
  await assert.rejects(
    () =>
      fetchVkProfile(
        { code: 'c', codeVerifier: 'v'.repeat(43), deviceId: 'd', redirectUri: 'r', state: 's' },
        { clientId: '1', fetchImpl },
      ),
    { status: 401 },
  );
});
