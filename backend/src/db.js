import { readdir, readFile } from 'node:fs/promises';
import pg from 'pg';
import { config } from './config.js';

// Дата (тип date) возвращается строкой YYYY-MM-DD, без сдвигов часовых поясов.
pg.types.setTypeParser(1082, (value) => value);

export const pool = new pg.Pool({ connectionString: config.databaseUrl, max: 10 });

pool.on('error', (err) => {
  console.error('[db] ошибка соединения в пуле:', err.message);
});

export const query = (text, params) => pool.query(text, params);

/** Выполняет fn внутри транзакции. При ошибке откатывает и пробрасывает её дальше. */
export async function tx(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // соединение уже недоступно, откатывать нечего
    }
    throw err;
  } finally {
    client.release();
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export async function waitForDb(retries = 30) {
  for (let i = 1; i <= retries; i++) {
    try {
      await pool.query('SELECT 1');
      return;
    } catch (err) {
      if (i === retries) throw err;
      console.log(`[db] ждём базу данных (${i}/${retries}): ${err.message}`);
      await sleep(1000);
    }
  }
}

const MIGRATIONS_DIR = new URL('./db/migrations/', import.meta.url);
const MIGRATION_LOCK = 727274;

/** Применяет новые файлы из src/db/migrations по порядку имён. Безопасно при нескольких копиях сервера. */
export async function migrate() {
  const files = (await readdir(MIGRATIONS_DIR)).filter((f) => f.endsWith('.sql')).sort();
  const client = await pool.connect();
  try {
    await client.query('SELECT pg_advisory_lock($1)', [MIGRATION_LOCK]);
    await client.query(
      `CREATE TABLE IF NOT EXISTS schema_migrations (
         name text PRIMARY KEY,
         applied_at timestamptz NOT NULL DEFAULT now()
       )`,
    );
    const { rows } = await client.query('SELECT name FROM schema_migrations');
    const done = new Set(rows.map((r) => r.name));

    for (const file of files) {
      if (done.has(file)) continue;
      const sql = await readFile(new URL(file, MIGRATIONS_DIR), 'utf8');
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
        await client.query('COMMIT');
        console.log(`[db] применена миграция ${file}`);
      } catch (err) {
        await client.query('ROLLBACK');
        throw new Error(`Миграция ${file} не применилась: ${err.message}`);
      }
    }
  } finally {
    await client.query('SELECT pg_advisory_unlock($1)', [MIGRATION_LOCK]).catch(() => {});
    client.release();
  }
}

/** Заливает демо-данные, если в базе ещё нет ни одной категории. */
export async function seedDemoIfEmpty() {
  const { rows } = await pool.query('SELECT count(*)::int AS n FROM categories');
  if (rows[0].n > 0) return false;
  const sql = await readFile(new URL('./db/seed.sql', import.meta.url), 'utf8');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(sql);
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw new Error(`Демо-данные не загрузились: ${err.message}`);
  } finally {
    client.release();
  }
  console.log('[db] загружены демо-данные (SEED_DEMO=true)');
  return true;
}

export async function closeDb() {
  await pool.end();
}
