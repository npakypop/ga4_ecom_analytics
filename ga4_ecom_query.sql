-- ==========================================================================================
-- Проєкт: E-commerce Analytics Hub (Аналіз воронки та атрибуції GA4)
-- Опис: Трансформація сирих логів GA4 для для аналізу в Tableau.
-- Сховище: Google BigQuery (Публічний анонімізований датасет ga4_obfuscated_sample_ecommerce)
-- ==========================================================================================

WITH sessions_info AS (
  -- 1: Формування даних сесії (Агрегація даних до рівня: 1 рядок = 1 унікальна сесія)
  SELECT
    -- Визначаємо дату старту сесії, переводячи її з текстового формату в тип DATE
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS session_date,
    
    -- Ідентифікатор користувача
    user_pseudo_id AS user_id,
    
    -- Створення композитного ключа сесії. Оскільки native ga_session_id дублюється у різних користувачів,
    -- ми склеюємо його з user_pseudo_id для отримання 100% унікального ID візиту.
    CONCAT(user_pseudo_id, ".", (SELECT value.int_value FROM e.event_params WHERE KEY = 'ga_session_id')) AS user_session_id,
    
    -- Порядковий номер сесії користувача
    MAX((SELECT value.int_value FROM e.event_params WHERE KEY = 'ga_session_number')) AS ga_session_number,
    
    -- Визначення посадкової сторінки (Landing Page).
    -- Шукаємо подію з параметром entrances = 1 (перший перегляд у сесії) та за допомогою REGEXP_EXTRACT
    -- очищаємо URL від домену, залишаючи лише чистий шлях сторінки (path).
    MAX(IF((SELECT value.int_value FROM e.event_params WHERE KEY = 'entrances') = 1, 
        REGEXP_EXTRACT((SELECT value.string_value FROM e.event_params WHERE KEY = 'page_location'), r'https?://[^/]+([^?#]*)'), 
        NULL)) AS landing_page,
        
    -- Технічні характеристики пристрою користувача
    MAX(device.category) AS device,
    MAX(device.operating_system) AS OS,
    MAX(device.language) AS device_language,
    
    -- МАРКЕТИНГОВА АТРИБУЦІЯ ПОТОЧНОЇ СЕСІЇ (Last-Touch)
    -- Особливість GA4: у події 'session_start' параметри джерела часто дорівнюють NULL.
    -- Завдяки фільтру WHERE ми аналізуємо 'session_start' разом із 'page_view'. 
    -- Функція MAX() ігнорує NULL та затягує реальне джерело трафіку з події першого перегляду сторінки.
    MAX((SELECT value.string_value FROM e.event_params WHERE KEY = 'source')) AS session_source,
    MAX((SELECT value.string_value FROM e.event_params WHERE KEY = 'medium')) AS session_medium,
    MAX((SELECT value.string_value FROM e.event_params WHERE KEY = 'campaign')) AS session_campaign,
    
    -- ДОДАВАННЯ ПЕРШого ДЖЕРЕЛА КОРИСТУВАЧА (First-Touch)
    -- Історичні дані з профілю користувача, які необхідні для побудови матриці порівняння джерел трафіку.
    MAX(traffic_source.source) AS first_source,
    MAX(traffic_source.medium) AS first_medium,
    MAX(traffic_source.name) AS first_campaign
    
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` as e
  -- беремо лише технічний старт та перший перегляд для збору метаданих сесії
  WHERE event_name IN ('session_start', 'page_view')
  GROUP BY user_id, user_session_id
),

events AS (
  -- 2: Хронологічна стрічка кроків воронки продажів
  SELECT
    -- Переводимо мікросекунди сервера в стандартний формат дати та часу TIMESTAMP
    TIMESTAMP_MICROS(event_timestamp) AS event_timestamp,
    event_name,
    
    -- Генеруємо такий самий композитний ключ сесії для подальшого об'єднання (JOIN)
    CONCAT(user_pseudo_id, ".", (SELECT value.int_value FROM e.event_params WHERE KEY = 'ga_session_id')) AS user_session_id,
    
    -- Дані про транзакції (наявні лише у події 'purchase')
    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue_in_usd AS revenue
    
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` e
  -- Фільтруємо лише 7 критичних івентів, які формують e-commerce воронку інтернет-магазину
  WHERE event_name IN (
    'session_start',     -- 1. Старт сесії
    'view_item',         -- 2. Перегляд товару
    'add_to_cart',       -- 3. Додавання в кошик
    'begin_checkout',    -- 4. Початок оформлення
    'add_shipping_info', -- 5. Введення даних доставки
    'add_payment_info',  -- 6. Введення платіжних даних
    'purchase'           -- 7. Фінальна покупка
  )
)

-- БЛОК 3: Фінальне об'єднання даних
SELECT
  s.*,                  -- Підтягуємо всі метадані та маркетингові джерела сесії
  e.event_timestamp,    -- Точний час здійснення продуктового кроку
  e.event_name,         -- Назва кроку воронки
  e.transaction_id,     -- Номер чеку
  
  -- Замінюємо порожні значення виручки (NULL) на 0 для коректної математичної агрегації в Tableau
  COALESCE(e.revenue, 0) AS revenue
  
FROM sessions_info s
-- Об'єднуємо таблиці за унікальним ID сесії. Використовуємо INNER JOIN, щоб відсікти сесії, 
-- які не згенерували жодної цільової дії з нашого списку подій воронки.
INNER JOIN events e ON s.user_session_id = e.user_session_id;