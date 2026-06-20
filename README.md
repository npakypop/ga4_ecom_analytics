# ga4_ecom_analytics

## Overview

This repository contains the GA4 e-commerce analytics project. It is intended to track, analyze, and report on e-commerce events and conversions using Google Analytics 4.

## Contents

- `README.md` — project documentation

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/<your-org>/ga4_ecom_analytics.git
   ```
2. Open the project in your preferred editor.

## Purpose

Use this project as a starting point for building GA4 e-commerce analytics implementations, event tracking plans, and reporting dashboards.

## Notes

- Add your GA4 configuration, tracking code, or analytics scripts as needed.
- Extend the repository with scripts, dashboards, or tracking documentation relevant to your implementation.

## SQL Query

- **File:** [ga4_ecom_query.sql](ga4_ecom_query.sql#L1-L48)
- **Purpose:** Извлечь информацию о сессиях и связанных с ними событиях электронной торговли (просмотры товаров, добавления в корзину, оформление заказа, покупки) и объединить их с данными о транзакциях и доходах.
- **Источник данных:** `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` (BigQuery public dataset).
- **Логика:**
   - `sessions_info`: собирает агрегированную информацию по сессии (дата сессии, `user_id`, `user_session_id`, номер сессии, посадочная страница, устройство, ОС, язык, источник/medium/campaign). Для извлечения источника используется параметр `entrances` из `page_view`, если в `session_start` он отсутствует.
   - `events`: выбирает временные метки событий, названия событий и данные электронной торговли (transaction_id, revenue) для набора ключевых событий (включая `purchase`).
   - Финальный `SELECT`: объединяет `sessions_info` и `events` по `user_session_id` и возвращает строки с деталями сессии и соответствующими событиями и доходом.
- **Выходные колонки (основные):** `session_date`, `user_id`, `user_session_id`, `ga_session_number`, `landing_page`, `device`, `OS`, `device_language`, `session_source`, `session_medium`, `session_campaign`, `first_source`, `first_medium`, `first_campaign`, `event_timestamp`, `event_name`, `transaction_id`, `revenue`.
- **Примечания:** Запрос написан для выполнения в BigQuery; при адаптации под вашу таблицу замените источник данных и, при необходимости, имена полей.
