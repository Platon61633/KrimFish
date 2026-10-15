import { normalizePhone } from './lib/phone.js';

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

  smsMode: env.SMS_MODE ?? 'console',
  // Фиксированный код входа для разработки (например 123456). В production игнорируется.
  smsFixedCode: !isProd && /^\d{6}$/.test(env.SMS_FIXED_CODE ?? '') ? env.SMS_FIXED_CODE : null,

  // Телефоны, которые при входе получают роль ADMIN.
  adminPhones: (env.ADMIN_PHONES ?? '')
    .split(',')
    .map((s) => normalizePhone(s.trim()))
    .filter(Boolean),

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
