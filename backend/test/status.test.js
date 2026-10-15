import assert from 'node:assert/strict';
import { test } from 'node:test';
import { canTransition } from '../src/lib/status.js';

test('статусы идут вперёд по цепочке', () => {
  assert.ok(canTransition('NEW', 'PREPARING'));
  assert.ok(canTransition('PREPARING', 'ON_THE_WAY'));
  assert.ok(canTransition('ON_THE_WAY', 'DELIVERED'));
});

test('пропуски и откаты запрещены', () => {
  assert.ok(!canTransition('NEW', 'ON_THE_WAY'));
  assert.ok(!canTransition('NEW', 'DELIVERED'));
  assert.ok(!canTransition('DELIVERED', 'PREPARING'));
  assert.ok(!canTransition('ON_THE_WAY', 'PREPARING'));
  assert.ok(!canTransition('NEW', 'NEW'));
});

test('отмена возможна только из NEW и PREPARING', () => {
  assert.ok(canTransition('NEW', 'CANCELED'));
  assert.ok(canTransition('PREPARING', 'CANCELED'));
  assert.ok(!canTransition('ON_THE_WAY', 'CANCELED'));
  assert.ok(!canTransition('DELIVERED', 'CANCELED'));
  assert.ok(!canTransition('CANCELED', 'CANCELED'));
  assert.ok(!canTransition('CANCELED', 'NEW'));
});
