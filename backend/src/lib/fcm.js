// Отправка push через Firebase Cloud Messaging (HTTP v1) без внешних библиотек:
// JWT сервисного аккаунта подписывается встроенным crypto.
import { createSign } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';

const b64u = (input) => Buffer.from(input).toString('base64url');

export function loadCredentials(file) {
  if (!file || !existsSync(file)) return null;
  try {
    const creds = JSON.parse(readFileSync(file, 'utf8'));
    if (!creds.client_email || !creds.private_key || !creds.project_id) return null;
    return creds;
  } catch {
    return null;
  }
}

export function signJwt(creds, nowMs = Date.now()) {
  const iat = Math.floor(nowMs / 1000);
  const header = b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64u(
    JSON.stringify({
      iss: creds.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: creds.token_uri ?? 'https://oauth2.googleapis.com/token',
      iat,
      exp: iat + 3600,
    }),
  );
  const signature = createSign('RSA-SHA256').update(`${header}.${claims}`).sign(creds.private_key);
  return `${header}.${claims}.${b64u(signature)}`;
}

/**
 * @returns {{enabled: boolean, send: (token: string, msg: {title: string, body: string, data?: object}) => Promise<'ok'|'invalid'>}}
 */
export function createFcm({ credentialsFile, fetchImpl = fetch, now = () => Date.now() }) {
  const creds = loadCredentials(credentialsFile);
  if (!creds) return { enabled: false, send: async () => 'ok' };

  let access = null; // { token, expiresAt }

  async function accessToken() {
    if (access && access.expiresAt - 60_000 > now()) return access.token;
    const res = await fetchImpl(creds.token_uri ?? 'https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: signJwt(creds, now()),
      }),
    });
    if (!res.ok) throw new Error(`Google OAuth: ${res.status} ${await res.text()}`);
    const j = await res.json();
    access = { token: j.access_token, expiresAt: now() + (j.expires_in ?? 3600) * 1000 };
    return access.token;
  }

  async function send(token, { title, body, data = {} }) {
    const res = await fetchImpl(
      `https://fcm.googleapis.com/v1/projects/${creds.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${await accessToken()}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
            android: { priority: 'HIGH' },
          },
        }),
      },
    );
    if (res.ok) return 'ok';
    const text = await res.text();
    // Токен устарел (приложение удалено или переустановлено) — его нужно забыть.
    if (res.status === 404 || text.includes('UNREGISTERED')) return 'invalid';
    throw new Error(`FCM: ${res.status} ${text}`);
  }

  return { enabled: true, send };
}
