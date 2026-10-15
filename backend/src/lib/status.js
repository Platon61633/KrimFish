export const STATUSES = ['NEW', 'PREPARING', 'ON_THE_WAY', 'DELIVERED', 'CANCELED'];

/** Статусы идут только вперёд. */
export const NEXT = {
  NEW: 'PREPARING',
  PREPARING: 'ON_THE_WAY',
  ON_THE_WAY: 'DELIVERED',
};

/** Отменить можно, пока заказ не уехал к клиенту. */
export const CANCELLABLE = ['NEW', 'PREPARING'];

export function canTransition(from, to) {
  if (to === 'CANCELED') return CANCELLABLE.includes(from);
  return NEXT[from] === to;
}
