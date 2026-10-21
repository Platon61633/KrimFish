import { normalizeEmail } from './lib/email.js';

const env = process.env;
const DEV_SECRET = 'dev-only-secret-change-me';

const int = (value, fallback) => {
  if (value === undefined || value === '') return fallback;
  const n = Number(value);
  return Number.isInteger(n) ? n : fallback;
};

const nodeEnv = env.NODE_ENV ?? 'development';
const isProd = nodeEnv === 'production';

export const config = {
  nodeEnv,
  isProd,
  port: int(env.PORT, 3000),
  databaseUrl: env.DATABASE_URL ?? 'postgres://krimfish:krimfish@localhost:5432/krimfish',

  jwtSecret: env.JWT_SECRET ?? DEV_SECRET,
  accessTokenTtl: env.ACCESS_TOKEN_TTL ?? '15m',
  refreshTokenTtlDays: int(env.REFRESH_TOKEN_TTL_DAYS, 30),

  // Администраторы. Роль ADMIN выдаётся только при подтверждённом входе:
  // через Google (email подтверждён Google) или по паролю ADMIN_PASSWORD, который сервер
  // сам задаёт этим адресам при старте. Обычная регистрация на такой адрес закрыта.
  adminEmails: (env.ADMIN_EMAILS ?? '')
    .split(',')
    .map((s) => normalizeEmail(s))
    .filter(Boolean),
  adminPassword: env.ADMIN_PASSWORD ?? '',

  // Вход через Google: Web client ID из Google Cloud (можно несколько через запятую).
  googleClientIds: (env.GOOGLE_CLIENT_ID ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),
  // Вход через VK ID: ID приложения и адрес возврата (vk<ID>://vk.ru/blank.html для мобильного приложения).
  vk: {
    clientId: (env.VK_CLIENT_ID ?? '').trim(),
    redirectUri: (env.VK_REDIRECT_URI ?? '').trim() || (env.VK_CLIENT_ID ? `vk${env.VK_CLIENT_ID.trim()}://vk.ru/blank.html` : ''),
  },

  // Письма (код подтверждения почты). console: код пишется в лог сервера и (вне production)
  // возвращается в ответе как devCode. smtp: настоящая отправка через SMTP_*.
  mail: {
    mode: env.MAIL_MODE ?? 'console',
    from: env.MAIL_FROM ?? 'KrimFish <noreply@krimfish.local>',
    smtp: {
      host: env.SMTP_HOST ?? '',
      secure: env.SMTP_SECURE ?? 'ssl', // ssl (465) | starttls (587) | none (только локальная проверка)
      port: int(env.SMTP_PORT, (env.SMTP_SECURE ?? 'ssl') === 'ssl' ? 465 : 587),
      user: env.SMTP_USER ?? '',
      password: env.SMTP_PASSWORD ?? '',
    },
  },

  corsOrigin: env.CORS_ORIGIN ?? '*',
  trustProxy: int(env.TRUST_PROXY, 0),

  timezone: env.APP_TZ ?? 'Europe/Moscow',
  slotDays: int(env.SLOT_DAYS, 2),
  slotLeadHours: int(env.SLOT_LEAD_HOURS, 1),
  deliveryKop: int(env.DELIVERY_KOP, 39000),

  // Хранилище фото (S3-совместимое). publicUrl — адрес, по которому до хранилища достаётся ТЕЛЕФОН/браузер.
  s3: {
    publicUrl: env.S3_PUBLIC_URL ?? 'http://localhost:9000',
    bucket: env.S3_BUCKET ?? 'krimfish',
    accessKey: env.S3_ACCESS_KEY ?? 'krimfish',
    secretKey: env.S3_SECRET_KEY ?? 'krimfish-secret',
    region: env.S3_REGION ?? 'us-east-1',
  },

  // Ключ сервисного аккаунта Firebase для push-уведомлений. Нет файла — уведомления выключены.
  firebaseCredentialsFile: env.FIREBASE_CREDENTIALS_FILE ?? '/run/secrets/firebase.json',

  seedDemo: (env.SEED_DEMO ?? (isProd ? 'false' : 'true')) === 'true',
};

if (isProd && (config.jwtSecret === DEV_SECRET || config.jwtSecret.length < 32)) {
  throw new Error('В production задайте JWT_SECRET длиной не меньше 32 символов');
}

if (config.adminPassword && config.adminPassword.length < (isProd ? 12 : 8)) {
  throw new Error(`ADMIN_PASSWORD слишком короткий (минимум ${isProd ? 12 : 8} символов)`);
}

if (!['console', 'smtp'].includes(config.mail.mode)) {
  throw new Error('MAIL_MODE должен быть console или smtp');
}
if (config.mail.mode === 'smtp' && !config.mail.smtp.host) {
  throw new Error('MAIL_MODE=smtp: задайте SMTP_HOST (и SMTP_USER, SMTP_PASSWORD)');
}
if (isProd && config.mail.mode !== 'smtp') {
  throw new Error('В production задайте MAIL_MODE=smtp и параметры SMTP_*: иначе коды из писем никому не придут');
}
