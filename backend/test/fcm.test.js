import assert from 'node:assert/strict';
import { createVerify, generateKeyPairSync } from 'node:crypto';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { createFcm, signJwt } from '../src/lib/fcm.js';

const { privateKey, publicKey } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  publicKeyEncoding: { type: 'spki', format: 'pem' },
});
const creds = {
  project_id: 'demo-project',
  client_email: 'svc@demo-project.iam.gserviceaccount.com',
  private_key: privateKey,
};
const file = join(mkdtempSync(join(tmpdir(), 'fcm-')), 'firebase.json');
writeFileSync(file, JSON.stringify(creds));

test('JWT подписан ключом сервисного аккаунта', () => {
  const jwt = signJwt(creds, 1_700_000_000_000);
  const [h, c, s] = jwt.split('.');
  const ok = createVerify('RSA-SHA256').update(`${h}.${c}`).verify(publicKey, Buffer.from(s, 'base64url'));
  assert.ok(ok);
  const claims = JSON.parse(Buffer.from(c, 'base64url'));
  assert.equal(claims.iss, creds.client_email);
  assert.equal(claims.exp - claims.iat, 3600);
});

test('без файла ключа уведомления выключены', async () => {
  const fcm = createFcm({ credentialsFile: '/нет/такого.json' });
  assert.equal(fcm.enabled, false);
  assert.equal(await fcm.send('t', { title: 'a', body: 'b' }), 'ok');
});

test('отправка: токен доступа берётся один раз, данные приводятся к строкам', async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes('oauth2')) {
      return new Response(JSON.stringify({ access_token: 'AT', expires_in: 3600 }), { status: 200 });
    }
    return new Response('{}', { status: 200 });
  };
  const fcm = createFcm({ credentialsFile: file, fetchImpl });
  assert.equal(fcm.enabled, true);
  assert.equal(await fcm.send('device-token', { title: 'T', body: 'B', data: { number: 1025 } }), 'ok');
  await fcm.send('device-token', { title: 'T2', body: 'B2' });

  assert.equal(calls.filter((c) => c.url.includes('oauth2')).length, 1);
  const sent = calls.filter((c) => c.url.includes('fcm.googleapis.com'));
  assert.equal(sent.length, 2);
  assert.ok(sent[0].url.includes('/projects/demo-project/messages:send'));
  assert.equal(sent[0].init.headers.Authorization, 'Bearer AT');
  const msg = JSON.parse(sent[0].init.body).message;
  assert.equal(msg.token, 'device-token');
  assert.deepEqual(msg.notification, { title: 'T', body: 'B' });
  assert.deepEqual(msg.data, { number: '1025' });
});

test('устаревший токен помечается invalid, прочие ошибки пробрасываются', async () => {
  const make = (status, text) =>
    createFcm({
      credentialsFile: file,
      fetchImpl: async (url) =>
        String(url).includes('oauth2')
          ? new Response(JSON.stringify({ access_token: 'AT', expires_in: 3600 }))
          : new Response(text, { status }),
    });
  assert.equal(await make(404, '{"error":{"status":"NOT_FOUND"}}').send('x', { title: 'a', body: 'b' }), 'invalid');
  await assert.rejects(make(500, 'boom').send('x', { title: 'a', body: 'b' }), /FCM: 500/);
});
