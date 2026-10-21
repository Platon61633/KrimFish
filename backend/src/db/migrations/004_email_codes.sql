-- Подтверждение почты при регистрации: аккаунт создаётся только после ввода кода из письма.
-- Пароль и имя ждут в этой таблице (хэш), пока владелец почты не подтвердит адрес.

CREATE TABLE email_codes (
  id             bigserial PRIMARY KEY,
  email          text NOT NULL,
  code_hash      text NOT NULL,
  password_hash  text NOT NULL,
  name           text,
  attempts       int  NOT NULL DEFAULT 0,
  expires_at     timestamptz NOT NULL,
  consumed_at    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX email_codes_email_idx ON email_codes (email, created_at DESC);
