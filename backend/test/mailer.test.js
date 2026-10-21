import assert from 'node:assert/strict';
import net from 'node:net';
import test from 'node:test';
import { bareAddress, buildMessage, sendViaSmtp } from '../src/lib/mailer.js';

/** Минимальный SMTP-сервер: запоминает команды и тело письма. */
function fakeSmtp({ rejectAuth = false } = {}) {
  const log = [];
  const server = net.createServer((socket) => {
    let data = false;
    let buf = '';
    socket.write('220 test\r\n');
    socket.on('data', (chunk) => {
      buf += chunk.toString();
      let i;
      while ((i = buf.indexOf(data ? '\r\n.\r\n' : '\r\n')) !== -1) {
        const piece = buf.slice(0, i);
        buf = buf.slice(i + (data ? 5 : 2));
        if (data) {
          data = false;
          log.push({ body: piece });
          socket.write('250 queued\r\n');
          continue;
        }
        log.push(piece);
        if (piece.startsWith('EHLO')) socket.write('250-test\r\n250 AUTH PLAIN\r\n');
        else if (piece.startsWith('AUTH')) socket.write(rejectAuth ? '535 no\r\n' : '235 ok\r\n');
        else if (piece === 'DATA') {
          data = true;
          socket.write('354 go\r\n');
        } else if (piece === 'QUIT') socket.end('221 bye\r\n');
        else socket.write('250 ok\r\n');
      }
    });
  });
  return new Promise((resolve) =>
    server.listen(0, '127.0.0.1', () => resolve({ server, log, port: server.address().port })),
  );
}

test('mailer: адрес без имени', () => {
  assert.equal(bareAddress('KrimFish <noreply@krimfish.ru>'), 'noreply@krimfish.ru');
  assert.equal(bareAddress('a@b.ru'), 'a@b.ru');
});

test('mailer: заголовки не пропускают перевод строки', () => {
  assert.throws(() => buildMessage({ from: 'a@b.ru', to: 'x@y.ru\r\nBcc: z@z.ru', subject: 's', text: 't' }));
  assert.throws(() => buildMessage({ from: 'a@b.ru', to: 'x@y.ru', subject: 's\nX: 1', text: 't' }));
});

test('mailer: письмо уходит по SMTP, русский текст и тема кодируются', async () => {
  const { server, log, port } = await fakeSmtp();
  try {
    await sendViaSmtp(
      { host: '127.0.0.1', port, secure: 'none', user: 'u', password: 'p' },
      { from: 'KrimFish <noreply@krimfish.ru>', to: 'ivan@mail.ru', subject: 'Код 123456', text: 'Ваш код: 123456\n.\nточка' },
    );
  } finally {
    server.close();
  }
  assert.ok(log.includes('MAIL FROM:<noreply@krimfish.ru>'));
  assert.ok(log.includes('RCPT TO:<ivan@mail.ru>'));
  assert.ok(log.some((l) => typeof l === 'string' && l.startsWith('AUTH PLAIN ')));
  const body = log.find((l) => l.body).body;
  const [head, payload] = body.split('\r\n\r\n');
  assert.match(head, /Subject: =\?UTF-8\?B\?/);
  assert.equal(Buffer.from(payload.replace(/\r\n/g, ''), 'base64').toString('utf8'), 'Ваш код: 123456\n.\nточка');
});

test('mailer: отказ в авторизации превращается в ошибку', async () => {
  const { server, port } = await fakeSmtp({ rejectAuth: true });
  try {
    await assert.rejects(
      sendViaSmtp(
        { host: '127.0.0.1', port, secure: 'none', user: 'u', password: 'bad' },
        { from: 'a@b.ru', to: 'c@d.ru', subject: 's', text: 't' },
      ),
      /535/,
    );
  } finally {
    server.close();
  }
});
