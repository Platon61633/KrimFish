import assert from 'node:assert/strict';
import { test } from 'node:test';
import { discountFor, formatRub, lineTotal } from '../src/lib/money.js';

test('весовой товар: граммы × цена за кг, округление до копейки', () => {
  assert.equal(lineTotal('kg', 258000, 500), 129000); // 500 г лосося по 2580 ₽/кг
  assert.equal(lineTotal('kg', 245000, 2000), 490000);
  assert.equal(lineTotal('kg', 79000, 333), 26307); // ровно 263,07 ₽
  assert.equal(lineTotal('kg', 100, 5), 1); // 0,5 копейки округляется вверх
});

test('штучный товар и набор: цена × количество', () => {
  assert.equal(lineTotal('piece', 5000, 3), 15000);
  assert.equal(lineTotal('set', 180000, 2), 360000);
});

test('итог из демо-корзины: 6 190 ₽ + доставка 390 ₽', () => {
  const items = lineTotal('kg', 258000, 500) + lineTotal('kg', 245000, 2000);
  assert.equal(items, 619000);
  assert.equal(items + 39000, 658000);
});

test('скидка: процент округляется вниз и не превышает сумму', () => {
  assert.equal(discountFor(619000, { percent: 10 }), 61900);
  assert.equal(discountFor(1999, { percent: 10 }), 199);
  assert.equal(discountFor(10000, { fixedKop: 30000 }), 10000);
  assert.equal(discountFor(10000, { percent: 10, fixedKop: 500 }), 1500);
  assert.equal(discountFor(10000), 0);
});

test('formatRub', () => {
  assert.equal(formatRub(150000), '1500 ₽');
  assert.equal(formatRub(150050), '1500,50 ₽');
});
