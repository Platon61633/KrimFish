/** Весовой товар продаётся кратно 100 г, минимум 300 г. */
export const MIN_WEIGHT_G = 300;
export const WEIGHT_STEP_G = 100;

export function isValidWeight(grams) {
  return Number.isInteger(grams) && grams >= MIN_WEIGHT_G && grams % WEIGHT_STEP_G === 0;
}
