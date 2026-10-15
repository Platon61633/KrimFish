import assert from 'node:assert/strict';
import { test } from 'node:test';
import { addDays, candidateSlots, nowInTz } from '../src/lib/time.js';

const templates = [
  { id: 'a', fromHour: 10, toHour: 11, capacity: 5 },
  { id: 'b', fromHour: 18, toHour: 19, capacity: 5 },
  { id: 'c', fromHour: 19, toHour: 20, capacity: 5 },
];

test('nowInTz учитывает часовой пояс (UTC 21:30 — это уже завтра в Москве)', () => {
  const now = new Date('2026-10-14T21:30:00Z');
  assert.deepEqual(nowInTz('UTC', now), { date: '2026-10-14', hour: 21 });
  assert.deepEqual(nowInTz('Europe/Moscow', now), { date: '2026-10-15', hour: 0 });
});

test('полночь не превращается в час 24', () => {
  const now = new Date('2026-10-14T21:05:00Z');
  assert.equal(nowInTz('Europe/Moscow', now).hour, 0);
});

test('addDays переходит через границу месяца и года', () => {
  assert.equal(addDays('2026-10-31', 1), '2026-11-01');
  assert.equal(addDays('2026-12-31', 1), '2027-01-01');
  assert.equal(addDays('2026-03-01', -1), '2026-02-28');
});

test('сегодняшние слоты скрываются, если до начала меньше leadHours', () => {
  const now = new Date('2026-10-14T15:30:00Z'); // 18:30 в Москве
  const slots = candidateSlots(templates, { tz: 'Europe/Moscow', days: 2, leadHours: 1, now });
  const today = slots.filter((s) => s.date === '2026-10-14').map((s) => s.slotId);
  const tomorrow = slots.filter((s) => s.date === '2026-10-15').map((s) => s.slotId);
  assert.deepEqual(today, ['c']); // 19–20 ещё можно, 18–19 уже нельзя
  assert.deepEqual(tomorrow, ['a', 'b', 'c']);
});

test('утром сегодня доступны все слоты, кроме уже начавшихся', () => {
  const now = new Date('2026-10-14T06:10:00Z'); // 09:10 в Москве
  const slots = candidateSlots(templates, { tz: 'Europe/Moscow', days: 1, leadHours: 1, now });
  assert.deepEqual(slots.map((s) => s.slotId), ['a', 'b', 'c']);
});

test('вечером сегодня слотов нет, остаётся завтра', () => {
  const now = new Date('2026-10-14T18:00:00Z'); // 21:00 в Москве
  const slots = candidateSlots(templates, { tz: 'Europe/Moscow', days: 2, leadHours: 1, now });
  assert.ok(slots.every((s) => s.date === '2026-10-15'));
  assert.equal(slots.length, 3);
});
