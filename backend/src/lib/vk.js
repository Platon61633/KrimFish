import { HttpError } from './errors.js';

// VK ID (OAuth 2.1 + PKCE). Адреса и поля написаны по документации VK ID по памяти:
// при подключении сверьте их с https://id.vk.com/about/business/go/docs
const AUTH_URL = 'https://id.vk.com/oauth2/auth';
const USER_INFO_URL = 'https://id.vk.com/oauth2/user_info';

const fail = (status = 401) => new HttpError(status, 'Не удалось выполнить вход через VK');

async function postForm(url, params, fetchImpl) {
  let res;
  try {
    res = await fetchImpl(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(params),
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    throw fail(502);
  }
  let json = null;
  try {
    json = await res.json();
  } catch {
    // тело не JSON
  }
  if (!res.ok || !json || json.error) {
    console.error('[vk]', url, res.status, json?.error, json?.error_description);
    throw fail();
  }
  return json;
}

/** Меняет код авторизации на токен и получает профиль. Возвращает { id, name }. */
export async function fetchVkProfile(
  { code, codeVerifier, deviceId, redirectUri, state },
  { clientId, fetchImpl = fetch },
) {
  const token = await postForm(
    AUTH_URL,
    {
      grant_type: 'authorization_code',
      code,
      code_verifier: codeVerifier,
      redirect_uri: redirectUri,
      client_id: clientId,
      device_id: deviceId,
      state,
    },
    fetchImpl,
  );
  if (!token.access_token) throw fail();

  const info = await postForm(
    USER_INFO_URL,
    { client_id: clientId, access_token: token.access_token },
    fetchImpl,
  );
  const user = info.user ?? {};
  const id = String(user.user_id ?? token.user_id ?? '');
  if (!id) throw fail();
  const name = [user.first_name, user.last_name].filter(Boolean).join(' ').trim();
  return { id, name: name || null };
}
