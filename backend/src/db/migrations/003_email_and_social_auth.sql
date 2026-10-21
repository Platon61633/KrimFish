-- Вход по email+паролю, Google и VK. Номер телефона больше не является логином:
-- он необязателен и вводится при оформлении заказа (для связи с курьером).

ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_phone_key;

ALTER TABLE users
  ADD COLUMN email           text UNIQUE,            -- всегда в нижнем регистре
  ADD COLUMN email_verified  boolean NOT NULL DEFAULT false,
  ADD COLUMN password_hash   text,
  ADD COLUMN google_sub      text UNIQUE,
  ADD COLUMN vk_id           text UNIQUE,
  ADD COLUMN failed_logins   int NOT NULL DEFAULT 0,
  ADD COLUMN locked_until    timestamptz;

ALTER TABLE users
  ADD CONSTRAINT users_has_identity
  CHECK (phone IS NOT NULL OR email IS NOT NULL OR google_sub IS NOT NULL OR vk_id IS NOT NULL);
