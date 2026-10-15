import assert from 'node:assert/strict';
import { test } from 'node:test';
import { presignPut, presignQuery } from '../src/lib/s3.js';

test('подпись совпадает с примером из документации AWS (presigned GET)', () => {
  const q = presignQuery({
    method: 'GET',
    host: 'examplebucket.s3.amazonaws.com',
    path: '/test.txt',
    accessKey: 'AKIAIOSFODNN7EXAMPLE',
    secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    region: 'us-east-1',
    expires: 86400,
    now: new Date('2013-05-24T00:00:00Z'),
  });
  assert.ok(q.endsWith('X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404'));
});

test('presignPut строит path-style ссылку', () => {
  const url = presignPut({
    publicUrl: 'http://localhost:9000',
    bucket: 'krimfish',
    key: 'products/a.jpg',
    accessKey: 'k',
    secretKey: 's',
    region: 'us-east-1',
  });
  assert.match(url, /^http:\/\/localhost:9000\/krimfish\/products\/a\.jpg\?X-Amz-Algorithm=/);
});
