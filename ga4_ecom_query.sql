-- CTE 1: Агрегація мета-даних на рівні сесії
WITH sessions_info AS (
  SELECT
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS session_date,
    user_pseudo_id AS user_id,
    -- Формуємо унікальний ID сесії (комбінація ID користувача та ID сесії)
    CONCAT(user_pseudo_id, ".", (SELECT value.int_value FROM e.event_params WHERE KEY = 'ga_session_id')) AS user_session_id,
    
    MAX((SELECT value.int_value FROM e.event_params WHERE KEY = 'ga_session_number')) AS ga_session_number,
    
    -- Визначаємо посадкову сторінку (Landing Page) за першим переглядом екрану (entrances = 1)
    MAX(IF((SELECT value.int_value FROM e.event_params WHERE KEY = 'entrances') = 1, 
        REGEXP_EXTRACT((SELECT value.string_value FROM e.event_params WHERE KEY = 'page_location'), r'https?://[^/]+([^?#]*)'), 
        NULL)) AS landing_page,
        
    -- Технічні характеристики пристрою користувача
    MAX(device.category) AS device,
    MAX(device.operating_system) AS OS,
    MAX(device.language) AS device_language,
    
    -- Маркетингові джерела поточної сесії (Session-level) для аналізу Last-Touch
    MAX((SELECT value.string_value FROM e.event_params WHERE KEY = 'source')) AS session_source,
    MAX((SELECT value.string_value FROM e.event_params WHERE KEY = 'medium')) AS session_medium,
    MAX((SELECT value.string_value FROM e.event_params WHERE KEY = 'campaign')) AS session_campaign,
    
    -- Джерела першого залучення користувача (User-level) для побудови шляху клієнта (First-Touch)
    MAX(traffic_source.source) AS first_source,
    MAX(traffic_source.medium) AS first_medium,
    MAX(traffic_source.name) AS first_campaign
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` as e
  -- Оскільки в події session_start часто відсутні маркетингові мітки, ми використовуємо 
  -- події page_view як "донора" даних та збираємо їх через MAX() у межах однієї сесії
  WHERE event_name IN ('session_start', 'page_view')
  GROUP BY user_id, user_session_id
),

-- CTE 2: Збір кроків комерційної воронки
events AS (
  SELECT
    TIMESTAMP_MICROS(event_timestamp) AS event_timestamp,
    event_name,
    CONCAT(user_pseudo_id, ".", (SELECT value.int_value FROM e.event_params WHERE KEY = 'ga_session_id')) AS user_session_id,
    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue_in_usd AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` e
  -- Включаємо session_start, щоб зберегти неконвертовані сесії для аналізу відвалів у Tableau,
  -- але навмисно виключаємо важкі рядки page_view для оптимізації обсягу даних та швидкості BI
  WHERE event_name IN ('session_start', 'view_item', 'add_to_cart', 'begin_checkout', 'add_shipping_info', 'add_payment_info', 'purchase')
)

-- Фінальний крок: формування денормалізованого датасету на рівні подій (Event-level grain)
SELECT
  s.*,
  e.event_timestamp,
  e.event_name,
  e.transaction_id,
  COALESCE(e.revenue, 0) AS revenue
FROM sessions_info s
-- INNER JOIN об'єднує мета-дані сесії з подіями воронки та відсікає технічні аномалії трекінгу
INNER JOIN events e ON s.user_session_id = e.user_session_id;