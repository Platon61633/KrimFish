import assert from 'node:assert/strict';
import { test } from 'node:test';
import { normalizePhone } from '../src/lib/phone.js';

test('приводит разные записи к +7XXXXXXXXXX', () => {
  assert.equal(normalizePhone('+7 (900) 123-45-67'), '+79001234567');
  assert.equal(normalizePhone('8 900 123 45 67'), '+79001234567');
  assert.equal(normalizePhone('9001234567'), '+79001234567');
  assert.equal(normalizePhone('79001234567'), '+79001234567');
});

test('иностранные номера сохраняются как есть', () => {
  assert.equal(normalizePhone('+44 20 7946 0958'), '+442079460958');
});

test('мусор отклоняется', () => {
  assert.equal(normalizePhone(''), null);
  assert.equal(normalizePhone('abc'), null);
  assert.equal(normalizePhone('12345'), null);
  assert.equal(normalizePhone('1'.repeat(16)), null);
  assert.equal(normalizePhone(null), null);
  assert.equal(normalizePhone(79001234567), null);
});
