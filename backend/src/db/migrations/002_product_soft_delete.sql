-- Удалённый товар не показывается нигде, но остаётся в базе: на него ссылаются старые заказы.
ALTER TABLE products ADD COLUMN deleted_at timestamptz;
