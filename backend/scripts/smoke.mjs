// Быстрая проверка запущенного сервера: вход, каталог, заказ, админка.
//
//   docker compose up -d --build
//   ADMIN_PHONE=+79990000001 npm run smoke
//
// Перед запуском в .env должно быть ADMIN_PHONES=+79990000001 (тот же номер), SMS_MODE=console.
// Нужен Node.js 20+ (встроенный fetch).

const BASE = process.env.API_URL ?? 'http://localhost:3000';
const ADMIN_PHONE = process.env.ADMIN_PHONE ?? '+79990000001';
const CUSTOMER_PHONE = process.env.CUSTOMER_PHONE ?? '+79990000002';

let step = 0;
function ok(message) {
  step += 1;
  console.log(`✓ ${String(step).padStart(2, '0')} ${message}`);
}

async function call(method, path, { token, body, headers } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  return { status: res.status, json };
}

function expect(condition, message, details) {
  if (!condition) {
    console.error(`✗ ${message}`);
    if (details !== undefined) console.error(JSON.stringify(details, null, 2));
    process.exit(1);
  }
}

async function login(phone) {
  const code = await call('POST', '/auth/request-code', { body: { phone } });
  if (code.status === 429) {
    console.error(`Код для ${phone} запрашивали меньше минуты назад. Подождите минуту и повторите.`);
    process.exit(1);
  }
  expect(code.status === 200 && code.json.devCode, 'не получили devCode (нужны SMS_MODE=console и NODE_ENV не production)', code);
  const session = await call('POST', '/auth/verify', { body: { phone, code: code.json.devCode } });
  expect(session.status === 200 && session.json.accessToken, 'вход по коду не удался', session);
  return session.json;
}

const health = await call('GET', '/health');
expect(health.status === 200, 'сервер не отвечает на /health', health);
ok('сервер и база доступны');

const products = await call('GET', '/products');
expect(products.status === 200 && products.json.length > 0, 'каталог пуст (SEED_DEMO=true?)', products);
ok(`каталог: ${products.json.length} товаров`);

const salmon = products.json.find((p) => p.name.startsWith('Лосось')) ?? products.json[0];
const slots = await call('GET', '/slots');
expect(slots.status === 200 && slots.json.length > 0, 'нет свободных слотов доставки', slots);
const slot = slots.json[0];
ok(`слотов доступно: ${slots.json.length}`);

const quote = await call('POST', '/cart/quote', {
  body: { items: [{ productId: salmon.id, qty: 500 }], promoCode: 'FISH10' },
});
expect(quote.status === 200, 'пересчёт корзины не удался', quote);
ok(`корзина: итого ${quote.json.totalKop / 100} ₽ (скидка ${quote.json.discountKop / 100} ₽)`);

const customer = await login(CUSTOMER_PHONE);
ok(`вход клиента ${customer.user.phone}`);

const orderBody = {
  items: [{ productId: salmon.id, qty: 500 }],
  slotId: slot.slotId,
  slotDate: slot.date,
  address: { line: 'ул. Примерная, 12' },
  promoCode: 'FISH10',
};
const key = `smoke-${Date.now()}`;
const created = await call('POST', '/orders', {
  token: customer.accessToken,
  body: orderBody,
  headers: { 'Idempotency-Key': key },
});
expect(created.status === 201, 'заказ не создан', created);
const repeated = await call('POST', '/orders', {
  token: customer.accessToken,
  body: orderBody,
  headers: { 'Idempotency-Key': key },
});
expect(repeated.status === 200 && repeated.json.number === created.json.number, 'повтор с тем же ключом создал новый заказ', repeated);
ok(`заказ №${created.json.number} оформлен, повторный запрос не создал дубль`);

const forbidden = await call('GET', '/admin/orders', { token: customer.accessToken });
expect(forbidden.status === 403, 'клиент получил доступ к админке', forbidden);
ok('клиенту админка закрыта (403)');

const admin = await login(ADMIN_PHONE);
expect(admin.user.role === 'ADMIN', `номер ${ADMIN_PHONE} не получил роль ADMIN: добавьте его в ADMIN_PHONES`, admin.user);
ok('вход администратора');

for (const to of ['PREPARING', 'ON_THE_WAY', 'DELIVERED']) {
  const r = await call('POST', `/admin/orders/${created.json.number}/transition`, {
    token: admin.accessToken,
    body: { to },
  });
  expect(r.status === 200 && r.json.status === to, `переход в ${to} не удался`, r);
}
ok('статусы: PREPARING → ON_THE_WAY → DELIVERED');

const back = await call('POST', `/admin/orders/${created.json.number}/transition`, {
  token: admin.accessToken,
  body: { to: 'PREPARING' },
});
expect(back.status === 409, 'откат статуса должен быть запрещён', back);
ok('откат статуса запрещён (409)');

const mine = await call('GET', '/orders', { token: customer.accessToken });
expect(mine.status === 200 && mine.json[0].status === 'DELIVERED', 'клиент не видит обновлённый статус', mine);
ok('клиент видит статус DELIVERED');

console.log('\nВсё работает.');
