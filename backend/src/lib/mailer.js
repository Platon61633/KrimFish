import crypto from 'node:crypto';
import net from 'node:net';
import tls from 'node:tls';
import { config } from '../config.js';
import { HttpError } from './errors.js';

const TIMEOUT_MS = 15_000;

/** Адрес без имени: "KrimFish <a@b.ru>" → "a@b.ru". */
export const bareAddress = (value) => /<([^<>\s]+)>/.exec(value)?.[1] ?? value.trim();

const encodeWord = (text) =>
  /^[\x20-\x7e]*$/.test(text) ? text : `=?UTF-8?B?${Buffer.from(text, 'utf8').toString('base64')}?=`;

/** "Имя <a@b.ru>" с нелатинским именем → безопасный для заголовка вид. */
function encodeFrom(from) {
  const m = /^(.*?)\s*<([^<>\s]+)>$/.exec(from.trim());
  if (!m || !m[1]) return from.trim();
  return `${encodeWord(m[1].replace(/^"|"$/g, ''))} <${m[2]}>`;
}

const noBreaks = (value, what) => {
  if (/[\r\n]/.test(value)) throw new Error(`Недопустимые символы в поле ${what}`);
  return value;
};

/** Собирает письмо (текст, UTF-8, base64). Точки в начале строк в base64 не встречаются. */
export function buildMessage({ from, to, subject, text, date = new Date(), host = 'krimfish' }) {
  const body = Buffer.from(text, 'utf8').toString('base64').match(/.{1,76}/g)?.join('\r\n') ?? '';
  return [
    `From: ${encodeFrom(noBreaks(from, 'From'))}`,
    `To: ${noBreaks(to, 'To')}`,
    `Subject: ${encodeWord(noBreaks(subject, 'Subject'))}`,
    `Date: ${date.toUTCString()}`,
    `Message-ID: <${crypto.randomUUID()}@${host}>`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: base64',
    '',
    body,
  ].join('\r\n');
}

/** Читает ответы SMTP: одна или несколько строк, последняя имеет вид "250 ...". */
function replyReader(socket) {
  let buffer = '';
  let waiter = null;
  let failure = null;

  const check = () => {
    if (!waiter) return;
    if (failure) {
      const w = waiter;
      waiter = null;
      w.reject(failure);
      return;
    }
    const parts = buffer.split('\r\n');
    const complete = parts.slice(0, -1);
    const last = complete.findIndex((l) => /^\d{3}( |$)/.test(l));
    if (last === -1) return;
    const lines = complete.slice(0, last + 1);
    buffer = parts.slice(last + 1).join('\r\n');
    const w = waiter;
    waiter = null;
    w.resolve({ code: Number(lines[last].slice(0, 3)), lines });
  };

  socket.on('data', (chunk) => {
    buffer += chunk.toString('utf8');
    check();
  });
  socket.on('error', (err) => {
    failure ??= err;
    check();
  });
  socket.on('close', () => {
    failure ??= new Error('соединение закрыто сервером');
    check();
  });

  return {
    next: () =>
      new Promise((resolve, reject) => {
        waiter = { resolve, reject };
        check();
      }),
  };
}

const connect = (smtp) =>
  new Promise((resolve, reject) => {
    const socket =
      smtp.secure === 'ssl'
        ? tls.connect({ host: smtp.host, port: smtp.port, servername: smtp.host })
        : net.connect({ host: smtp.host, port: smtp.port });
    socket.setTimeout(TIMEOUT_MS, () => socket.destroy(new Error('таймаут соединения')));
    socket.once('error', reject);
    socket.once(smtp.secure === 'ssl' ? 'secureConnect' : 'connect', () => {
      socket.off('error', reject);
      resolve(socket);
    });
  });

/**
 * Отправляет письмо по SMTP без внешних библиотек.
 * smtp.secure: 'ssl' (порт 465), 'starttls' (порт 587) или 'none' (только для локальной проверки).
 */
export async function sendViaSmtp(smtp, { from, to, subject, text }) {
  let socket = await connect(smtp);
  let reader = replyReader(socket);

  const expect = async (codes, label) => {
    const reply = await reader.next();
    if (!codes.includes(reply.code)) {
      throw new Error(`${label}: SMTP ${reply.code} ${reply.lines.join(' ')}`);
    }
    return reply;
  };
  const command = async (line, codes) => {
    socket.write(`${line}\r\n`);
    return expect(codes, line.split(' ')[0]);
  };

  try {
    await expect([220], 'приветствие');
    await command('EHLO krimfish', [250]);

    if (smtp.secure === 'starttls') {
      await command('STARTTLS', [220]);
      socket.removeAllListeners('data');
      socket = await new Promise((resolve, reject) => {
        const upgraded = tls.connect({ socket, servername: smtp.host }, () => resolve(upgraded));
        upgraded.once('error', reject);
        upgraded.setTimeout(TIMEOUT_MS, () => upgraded.destroy(new Error('таймаут TLS')));
      });
      reader = replyReader(socket);
      await command('EHLO krimfish', [250]);
    }

    if (smtp.user) {
      const token = Buffer.from(`\0${smtp.user}\0${smtp.password}`).toString('base64');
      await command(`AUTH PLAIN ${token}`, [235]);
    }

    await command(`MAIL FROM:<${bareAddress(from)}>`, [250]);
    await command(`RCPT TO:<${bareAddress(to)}>`, [250, 251]);
    await command('DATA', [354]);
    socket.write(`${buildMessage({ from, to, subject, text })}\r\n.\r\n`);
    await expect([250], 'отправка письма');
    socket.write('QUIT\r\n');
  } finally {
    socket.destroy();
  }
}

/** Отправка письма. В режиме console код просто пишется в лог сервера (для разработки). */
export async function sendMail({ to, subject, text }) {
  if (config.mail.mode === 'console') {
    console.log(`[mail] кому: ${to}\n[mail] тема: ${subject}\n[mail] ${text}`);
    return;
  }
  try {
    await sendViaSmtp(config.mail.smtp, { from: config.mail.from, to, subject, text });
  } catch (err) {
    console.error('[mail] не удалось отправить письмо:', err.message);
    throw new HttpError(502, 'Не удалось отправить письмо. Попробуйте позже');
  }
}
