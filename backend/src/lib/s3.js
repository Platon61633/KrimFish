// Presigned-ссылки для S3-совместимого хранилища (MinIO, Yandex Object Storage, AWS S3).
// AWS Signature V4 на встроенном crypto — без внешних зависимостей.
import { createHash, createHmac } from 'node:crypto';

const hmac = (key, data) => createHmac('sha256', key).update(data).digest();
const sha256hex = (data) => createHash('sha256').update(data).digest('hex');
const enc = (s) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

/**
 * @param {{method:string, host:string, path:string, accessKey:string, secretKey:string,
 *          region:string, expires:number, now?:Date}} p
 * @returns {string} query string подписи (без "?")
 */
export function presignQuery({ method, host, path, accessKey, secretKey, region, expires, now = new Date() }) {
  const amzDate = now.toISOString().replace(/[-:]|\.\d{3}/g, ''); // 20130524T000000Z
  const day = amzDate.slice(0, 8);
  const scope = `${day}/${region}/s3/aws4_request`;
  const params = {
    'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
    'X-Amz-Credential': `${accessKey}/${scope}`,
    'X-Amz-Date': amzDate,
    'X-Amz-Expires': String(expires),
    'X-Amz-SignedHeaders': 'host',
  };
  const query = Object.keys(params)
    .sort()
    .map((k) => `${enc(k)}=${enc(params[k])}`)
    .join('&');
  const canonicalPath = path.split('/').map(enc).join('/');
  const canonical = [method, canonicalPath, query, `host:${host}\n`, 'host', 'UNSIGNED-PAYLOAD'].join('\n');
  const toSign = ['AWS4-HMAC-SHA256', amzDate, scope, sha256hex(canonical)].join('\n');
  const kDate = hmac(`AWS4${secretKey}`, day);
  const signingKey = hmac(hmac(hmac(kDate, region), 's3'), 'aws4_request');
  const signature = createHmac('sha256', signingKey).update(toSign).digest('hex');
  return `${query}&X-Amz-Signature=${signature}`;
}

/** Ссылка для загрузки файла методом PUT (path-style: https://host/bucket/key). */
export function presignPut({ publicUrl, bucket, key, accessKey, secretKey, region, expires = 600, now }) {
  const base = new URL(publicUrl);
  const prefix = base.pathname.replace(/\/$/, '');
  const path = `${prefix}/${bucket}/${key}`;
  const q = presignQuery({ method: 'PUT', host: base.host, path, accessKey, secretKey, region, expires, now });
  return `${base.origin}${path.split('/').map(enc).join('/')}?${q}`;
}

export const publicObjectUrl = ({ publicUrl, bucket, key }) =>
  `${publicUrl.replace(/\/$/, '')}/${bucket}/${key}`;
