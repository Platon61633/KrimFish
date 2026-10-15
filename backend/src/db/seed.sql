-- Демо-данные. Применяются один раз, если таблица категорий пуста и SEED_DEMO=true.
-- Названия и цены примерные, замените на свои через админку.

INSERT INTO categories (name, sort) VALUES
  ('Рыба', 1),
  ('Креветки', 2),
  ('Устрицы', 3),
  ('Моллюски', 4);

INSERT INTO products (category_id, name, description, unit, price_kop, weight_steps, stock) VALUES
  ((SELECT id FROM categories WHERE name = 'Рыба'),
   'Лосось охлаждённый', 'Стейк без кожи для запекания и гриля.',
   'kg', 258000, '{300,500,1000}', 12000),
  ((SELECT id FROM categories WHERE name = 'Креветки'),
   'Тигровые креветки', 'Крупные креветки в панцире.',
   'kg', 245000, '{500,1000,2000}', 9000),
  ((SELECT id FROM categories WHERE name = 'Устрицы'),
   'Устрицы, 6 шт', 'Набор из шести устриц в раковине.',
   'set', 180000, '{}', 3),
  ((SELECT id FROM categories WHERE name = 'Моллюски'),
   'Мидии', 'Мидии в раковине.',
   'kg', 79000, '{500,1000}', 8000);

INSERT INTO delivery_slots (from_hour, to_hour, capacity) VALUES
  (10, 11, 5),
  (12, 13, 5),
  (18, 19, 5),
  (19, 20, 5);

INSERT INTO promo_codes (code, percent_off) VALUES ('FISH10', 10);
