import { config } from '../config.js';
import { HttpError } from './errors.js';

/**
 * Отправка СМС. В режиме console код просто пишется в лог сервера (для разработки).
 * Чтобы подключить реального провайдера, добавьте ветку по SMS_MODE и вызовите его API.
 */
export async function sendSms(phone, text) {
  if (config.smsMode === 'console') {
    console.log(`[sms] ${phone}: ${text}`);
    return;
  }
  throw new HttpError(
    502,
    `СМС-провайдер "${config.smsMode}" не подключён: допишите src/lib/sms.js`,
  );
}
