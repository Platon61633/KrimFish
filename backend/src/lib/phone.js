/**
 * Приводит номер к виду +79001234567.
 * 8XXXXXXXXXX → +7XXXXXXXXXX, 10 цифр считаются российским номером без кода страны.
 * Возвращает null, если номер не похож на телефон.
 */
export function normalizePhone(input) {
  if (typeof input !== 'string') return null;
  let digits = input.replace(/\D/g, '');
  if (digits.length === 11 && digits.startsWith('8')) digits = `7${digits.slice(1)}`;
  if (digits.length === 10) digits = `7${digits}`;
  if (digits.length < 11 || digits.length > 15) return null;
  return `+${digits}`;
}
