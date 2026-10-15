import { query } from '../db.js';
import { config } from '../config.js';
import { HttpError } from '../lib/errors.js';
import { candidateSlots } from '../lib/time.js';

const TEMPLATES_SQL = `SELECT id, from_hour AS "fromHour", to_hour AS "toHour", capacity
                       FROM delivery_slots WHERE is_active ORDER BY from_hour`;

const slotOptions = () => ({
  tz: config.timezone,
  days: config.slotDays,
  leadHours: config.slotLeadHours,
});

/** Свободные слоты на ближайшие дни (занятые по вместимости не показываются). */
export async function listAvailableSlots() {
  const { rows: templates } = await query(TEMPLATES_SQL);
  const candidates = candidateSlots(templates, slotOptions());
  if (candidates.length === 0) return [];

  const dates = [...new Set(candidates.map((c) => c.date))];
  const { rows: load } = await query(
    `SELECT slot_id AS "slotId", slot_date::text AS "date", count(*)::int AS n
       FROM orders
      WHERE slot_date = ANY($1::date[]) AND status <> 'CANCELED'
      GROUP BY slot_id, slot_date`,
    [dates],
  );
  const used = new Map(load.map((r) => [`${r.slotId}|${r.date}`, r.n]));

  return candidates
    .filter((c) => (used.get(`${c.slotId}|${c.date}`) ?? 0) < c.capacity)
    .map(({ capacity: _capacity, ...slot }) => slot);
}

/**
 * Проверяет слот при оформлении заказа. В транзакции блокирует строку слота,
 * поэтому два заказа не займут последнее место одновременно.
 */
export async function loadSlot(db, slotId, slotDate, { lock = false } = {}) {
  const { rows } = await db.query(
    `SELECT id, from_hour AS "fromHour", to_hour AS "toHour", capacity
       FROM delivery_slots WHERE id = $1 AND is_active${lock ? ' FOR UPDATE' : ''}`,
    [slotId],
  );
  const template = rows[0];
  if (!template) throw new HttpError(400, 'Слот доставки не найден');

  const allowed = candidateSlots([template], slotOptions()).some((c) => c.date === slotDate);
  if (!allowed) throw new HttpError(400, 'Это время доставки уже недоступно');

  const { rows: load } = await db.query(
    `SELECT count(*)::int AS n FROM orders
      WHERE slot_id = $1 AND slot_date = $2::date AND status <> 'CANCELED'`,
    [slotId, slotDate],
  );
  if (load[0].n >= template.capacity) {
    throw new HttpError(409, 'Это время доставки занято, выберите другое');
  }
  return { id: template.id, date: slotDate, fromHour: template.fromHour, toHour: template.toHour };
}
