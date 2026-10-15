/** Текущая дата (YYYY-MM-DD) и час в заданном часовом поясе. */
export function nowInTz(tz, now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(now);
  const get = (type) => parts.find((p) => p.type === type).value;
  return {
    date: `${get('year')}-${get('month')}-${get('day')}`,
    hour: Number(get('hour')),
  };
}

export function addDays(dateStr, n) {
  const [y, m, d] = dateStr.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/**
 * Слоты, которые можно выбрать сейчас: на ближайшие `days` дней.
 * Сегодняшний слот доступен, если до его начала осталось не меньше `leadHours` часов.
 */
export function candidateSlots(templates, { tz, days, leadHours, now = new Date() }) {
  const cur = nowInTz(tz, now);
  const out = [];
  for (let i = 0; i < days; i++) {
    const date = addDays(cur.date, i);
    for (const t of templates) {
      if (i === 0 && t.fromHour < cur.hour + leadHours) continue;
      out.push({
        slotId: t.id,
        date,
        fromHour: t.fromHour,
        toHour: t.toHour,
        capacity: t.capacity,
      });
    }
  }
  return out;
}
