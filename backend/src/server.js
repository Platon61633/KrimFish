import { createApp } from './app.js';
import { config } from './config.js';
import { fcm } from './services/notify.js';
import { closeDb, migrate, seedDemoIfEmpty, waitForDb } from './db.js';

async function main() {
  await waitForDb();
  await migrate();
  if (config.seedDemo) await seedDemoIfEmpty();

  const app = createApp();
  const server = app.listen(config.port, () => {
    console.log(`KrimFish API слушает порт ${config.port} (${config.nodeEnv})`);
    console.log(
      fcm.enabled
        ? 'Push-уведомления включены (Firebase)'
        : `Push-уведомления выключены: нет ключа Firebase (${config.firebaseCredentialsFile})`,
    );
    if (config.adminPhones.length === 0) {
      console.log('ADMIN_PHONES не задан: ни один пользователь не получит роль администратора');
    }
  });

  let stopping = false;
  const shutdown = (signal) => {
    if (stopping) return;
    stopping = true;
    console.log(`Получен ${signal}, останавливаемся…`);
    server.close(async () => {
      await closeDb().catch(() => {});
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10_000).unref();
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

main().catch((err) => {
  console.error('Не удалось запустить сервер:', err);
  process.exit(1);
});
