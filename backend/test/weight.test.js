import assert from 'node:assert/strict';
import { test } from 'node:test';
import { isValidWeight } from '../src/lib/weight.js';

test('вес: от 300 г и кратно 100 г', () => {
  for (const g of [300, 400, 500, 1000, 2500]) assert.equal(isValidWeight(g), true, String(g));
  for (const g of [0, 100, 200, 299, 350, 301, 1050, -300, 300.5]) {
    assert.equal(isValidWeight(g), false, String(g));
  }
});
