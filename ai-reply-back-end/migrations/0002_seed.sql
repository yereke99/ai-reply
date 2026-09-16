-- 0002_seed: бастапқы тарифтер мен модель бағасы. Лимиттер кодта емес, осында.
INSERT INTO plans (id, code, name_kk, name_ru, name_en, name_uz,
                   description_kk, description_ru, description_en, description_uz,
                   price, currency, daily_message_limit, monthly_message_limit, period_days,
                   is_free, is_active, sort_order, created_at, updated_at)
VALUES
 ('00000000-0000-4000-8000-000000000001', 'free',
  'Тегін', 'Бесплатный', 'Free', 'Bepul',
  'Күніне 7 жауап. Картасыз бастаңыз.',
  '7 ответов в день. Начните без карты.',
  '7 replies per day. Start without a card.',
  'Kuniga 7 ta javob. Kartasiz boshlang.',
  0, 'KZT', 7, 0, 0, 1, 1, 10, 0, 0),
 ('00000000-0000-4000-8000-000000000002', 'standard',
  'Стандарт', 'Стандарт', 'Standard', 'Standart',
  'Күніне 30 жауап. Күнделікті жазысу үшін.',
  '30 ответов в день. Для ежедневной переписки.',
  '30 replies per day. For everyday messaging.',
  '30 ta javob kuniga. Kundalik yozishmalar uchun.',
  199000, 'KZT', 30, 0, 30, 0, 1, 20, 0, 0),
 ('00000000-0000-4000-8000-000000000003', 'pro',
  'Pro', 'Pro', 'Pro', 'Pro',
  'Күніне 50 жауап. Сатылым мен қолдау үшін.',
  '50 ответов в день. Для продаж и поддержки.',
  '50 replies per day. For sales and support.',
  'Kuniga 50 ta javob. Sotuv va qoʻllab-quvvatlash uchun.',
  349000, 'KZT', 50, 0, 30, 0, 1, 30, 0, 0);

INSERT INTO model_pricing (id, model, input_price_per_1m, output_price_per_1m, currency, effective_from, created_at)
VALUES ('00000000-0000-4000-8000-000000000101', 'gpt-4o-mini', 0.15, 0.60, 'USD', 0, 0);

INSERT INTO system_settings (key, value, updated_at) VALUES
 ('default_plan_code', 'free', 0),
 ('quota_timezone_note', 'Күндік квота сервер уақыт белдеуі бойынша қайта жаңарады.', 0);
