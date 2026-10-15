import { query } from '../db.js';
import { config } from '../config.js';
import { createFcm } from '../lib/fcm.js';
import { formatRub } from '../lib/money.js';

export const fcm = createFcm({ credentialsFile: config.firebaseCredentialsFile });

async function deliver(rows, msg) {
  for (const { token } of rows) {
    try {
      if ((await fcm.send(token, msg)) === 'invalid') {
        await query('DELETE FROM devices WHERE token = $1', [token]);
      }
    } catch (err) {
      console.error('[push]', err.message);
    }
  }
}

/** Уведомления не должны ломать основной запрос: ошибки только пишем в лог. */
function background(fn) {
  if (!fcm.enabled) return;
  fn().catch((err) => console.error('[push]', err.message));
}

function toUser(userId, msg) {
  background(async () => {
    const { rows } = await query('SELECT token FROM devices WHERE user_id = $1', [userId]);
    await deliver(rows, msg);
  });
}

function toAdmins(msg) {
  background(async () => {
    const { rows } = await query(
      `SELECT d.token FROM devices d JOIN users u ON u.id = d.user_id
        WHERE u.role = 'ADMIN' AND u.deleted_at IS NULL`,
    );
    await deliver(rows, msg);
  });
}

const data = (order) => ({ type: 'order', number: order.number, status: order.status });

export function notifyNewOrder(order) {
  const who = order.customerName || order.customerPhone;
  toAdmins({
    title: `Новый заказ №${order.number}`,
    body: `${who} · ${formatRub(order.totalKop)}`,
    data: data(order),
  });
}

export function notifyClientCanceled(order) {
  toAdmins({
    title: `Заказ №${order.number} отменён клиентом`,
    body: formatRub(order.totalKop),
    data: data(order),
  });
}

const STATUS_TEXT = {
  PREPARING: ['собирается', 'Мы начали собирать ваш заказ'],
  ON_THE_WAY: ['в пути', 'Заказ выехал к вам'],
  DELIVERED: ['доставлен', 'Приятного аппетита!'],
  CANCELED: ['отменён', 'Если это ошибка, свяжитесь с нами'],
};

/** Клиенту: статус его заказа изменился. */
export function notifyStatus(order) {
  const text = STATUS_TEXT[order.status];
  if (!text || !order.userId) return;
  toUser(order.userId, {
    title: `Заказ №${order.number} ${text[0]}`,
    body: text[1],
    data: data(order),
  });
}
