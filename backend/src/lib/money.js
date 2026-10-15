/**
 * Сумма строки заказа в копейках.
 * Для весового товара (kg) количество в граммах, а цена за килограмм; остальное считается поштучно.
 * Округление до ближайшей копейки (половина вверх), только целые числа.
 */
export function lineTotal(unit, priceKop, qty) {
  return unit === 'kg' ? Math.floor((priceKop * qty + 500) / 1000) : priceKop * qty;
}

/** Скидка не может превысить сумму товаров. Процент округляется вниз. */
export function discountFor(itemsKop, { percent = 0, fixedKop = 0 } = {}) {
  const byPercent = Math.floor((itemsKop * percent) / 100);
  return Math.min(itemsKop, byPercent + fixedKop);
}

export function formatRub(kop) {
  const rub = kop / 100;
  return Number.isInteger(rub) ? `${rub} ₽` : `${rub.toFixed(2).replace('.', ',')} ₽`;
}
