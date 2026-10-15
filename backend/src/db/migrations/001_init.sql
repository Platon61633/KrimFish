-- KrimFish: начальная схема.
-- Деньги хранятся в копейках (int), вес в граммах.

CREATE TABLE users (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone       text NOT NULL UNIQUE,
  name        text,
  role        text NOT NULL DEFAULT 'CUSTOMER' CHECK (role IN ('CUSTOMER', 'ADMIN')),
  bonus       int  NOT NULL DEFAULT 0 CHECK (bonus >= 0),
  created_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz
);

CREATE TABLE auth_codes (
  id           bigserial PRIMARY KEY,
  phone        text NOT NULL,
  code_hash    text NOT NULL,
  attempts     int  NOT NULL DEFAULT 0,
  expires_at   timestamptz NOT NULL,
  consumed_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auth_codes_phone_idx ON auth_codes (phone, created_at DESC);

CREATE TABLE refresh_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token_hash  text NOT NULL UNIQUE,
  expires_at  timestamptz NOT NULL,
  revoked_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user_idx ON refresh_tokens (user_id);

CREATE TABLE addresses (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  line        text NOT NULL,
  flat        text,
  note        text,
  lat         double precision,
  lng         double precision,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX addresses_user_idx ON addresses (user_id);

CREATE TABLE devices (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token       text NOT NULL UNIQUE,
  os          text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE categories (
  id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name  text NOT NULL UNIQUE,
  sort  int  NOT NULL DEFAULT 0
);

CREATE TABLE products (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id  uuid NOT NULL REFERENCES categories (id),
  name         text NOT NULL,
  description  text NOT NULL DEFAULT '',
  image_url    text,
  unit         text NOT NULL CHECK (unit IN ('kg', 'piece', 'set')),
  price_kop    int  NOT NULL CHECK (price_kop > 0),          -- за кг / штуку / набор
  weight_steps int[] NOT NULL DEFAULT '{}',                   -- порции для кг, граммы
  stock        int  NOT NULL DEFAULT 0 CHECK (stock >= 0),    -- граммы для кг, штуки для остальных
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX products_category_idx ON products (category_id);

-- Шаблоны слотов доставки: повторяются каждый день.
CREATE TABLE delivery_slots (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_hour  int NOT NULL CHECK (from_hour BETWEEN 0 AND 23),
  to_hour    int NOT NULL CHECK (to_hour BETWEEN 1 AND 24),
  capacity   int NOT NULL DEFAULT 5 CHECK (capacity > 0),     -- сколько заказов успеваете за слот
  is_active  boolean NOT NULL DEFAULT true,
  CHECK (to_hour > from_hour),
  UNIQUE (from_hour, to_hour)
);

CREATE TABLE promo_codes (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code             text NOT NULL UNIQUE,
  percent_off      int CHECK (percent_off BETWEEN 1 AND 100),
  amount_off_kop   int CHECK (amount_off_kop > 0),
  min_order_kop    int NOT NULL DEFAULT 0 CHECK (min_order_kop >= 0),
  uses_left        int CHECK (uses_left >= 0),                -- NULL = без ограничений
  is_active        boolean NOT NULL DEFAULT true,
  CHECK (percent_off IS NOT NULL OR amount_off_kop IS NOT NULL)
);

CREATE SEQUENCE order_number_seq START 1024;

CREATE TABLE orders (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number              int  NOT NULL UNIQUE DEFAULT nextval('order_number_seq'),
  user_id             uuid NOT NULL REFERENCES users (id),
  status              text NOT NULL DEFAULT 'NEW'
                      CHECK (status IN ('NEW', 'PREPARING', 'ON_THE_WAY', 'DELIVERED', 'CANCELED')),
  slot_id             uuid NOT NULL REFERENCES delivery_slots (id),
  slot_date           date NOT NULL,
  slot_from           int  NOT NULL,
  slot_to             int  NOT NULL,
  customer_name       text NOT NULL,
  customer_phone      text NOT NULL,
  address_line        text NOT NULL,
  address_note        text,
  items_kop           int  NOT NULL CHECK (items_kop >= 0),
  discount_kop        int  NOT NULL DEFAULT 0 CHECK (discount_kop >= 0),
  delivery_kop        int  NOT NULL CHECK (delivery_kop >= 0),
  total_kop           int  NOT NULL CHECK (total_kop >= 0),
  promo_code          text,
  discount_percent    int  NOT NULL DEFAULT 0,
  discount_fixed_kop  int  NOT NULL DEFAULT 0,
  payment_status      text NOT NULL DEFAULT 'PENDING'
                      CHECK (payment_status IN ('PENDING', 'HELD', 'PAID', 'REFUNDED', 'FAILED')),
  payment_ref         text,
  idempotency_key     text,
  comment             text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, idempotency_key)
);
CREATE INDEX orders_status_idx ON orders (status, created_at DESC);
CREATE INDEX orders_user_idx   ON orders (user_id, created_at DESC);
CREATE INDEX orders_slot_idx   ON orders (slot_id, slot_date);

CREATE TABLE order_items (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id       uuid NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
  position       int  NOT NULL,
  product_id     uuid NOT NULL REFERENCES products (id),
  name_snapshot  text NOT NULL,                 -- название и цена копируются на момент заказа
  unit           text NOT NULL,
  price_kop      int  NOT NULL,
  ordered_qty    int  NOT NULL CHECK (ordered_qty > 0),
  actual_qty     int  CHECK (actual_qty > 0)    -- фактический вес после сборки
);
CREATE INDEX order_items_order_idx ON order_items (order_id, position);
