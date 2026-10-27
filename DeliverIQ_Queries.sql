create database deliveriq;
-- =====================================================================
-- DeliverIQ: all SQL so far
-- Run ONE block at a time: highlight the block, then click the lightning bolt.
-- Save this file in D:\DeliverIQ\sql\ so it never gets lost.
-- =====================================================================

USE deliveriq;

-- ---------------------------------------------------------------------
-- 0. Quick health check: do the tables and view exist?
-- ---------------------------------------------------------------------
SHOW FULL TABLES;

-- ---------------------------------------------------------------------
-- 1. Indexes (speed up joins). Run once. "Duplicate key name" = already exists, ignore.
-- ---------------------------------------------------------------------
CREATE INDEX idx_orders_order_id      ON orders (order_id(32));
CREATE INDEX idx_orders_customer_id   ON orders (customer_id(32));
CREATE INDEX idx_customers_id         ON customers (customer_id(32));
CREATE INDEX idx_items_order_id       ON order_items (order_id(32));
CREATE INDEX idx_items_product_id     ON order_items (product_id(32));
CREATE INDEX idx_items_seller_id      ON order_items (seller_id(32));
CREATE INDEX idx_products_id          ON products (product_id(32));
CREATE INDEX idx_products_category    ON products (product_category_name(60));
CREATE INDEX idx_trans_category       ON product_category_name_translation (product_category_name(60));
CREATE INDEX idx_reviews_order_id     ON order_reviews (order_id(32));
CREATE INDEX idx_payments_order_id    ON order_payments (order_id(32));
CREATE INDEX idx_sellers_id           ON sellers (seller_id(32));

-- ---------------------------------------------------------------------
-- 2. Row counts
-- ---------------------------------------------------------------------
SELECT 'orders' AS table_name, COUNT(*) AS total_rows FROM orders
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL SELECT 'product_category_name_translation', COUNT(*) FROM product_category_name_translation;

-- ---------------------------------------------------------------------
-- 3. Data quality checks
-- ---------------------------------------------------------------------
-- 3a. Order statuses
SELECT order_status, COUNT(*) AS total
FROM orders
GROUP BY order_status
ORDER BY total DESC;

-- 3b. Duplicate orders (want 0 rows)
SELECT order_id, COUNT(*) AS times
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;

-- 3c. Delivered orders with no delivery date (result: 8)
SELECT COUNT(*) AS missing_delivery_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- 3d. Late orders (result: 7,826)
SELECT COUNT(*) AS late_orders
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date > order_estimated_delivery_date;

-- ---------------------------------------------------------------------
-- 4. Main view: delivered orders with real dates and a late flag
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_delivered_orders AS
SELECT
    order_id,
    customer_id,
    CAST(order_purchase_timestamp AS DATETIME)       AS purchase_date,
    CAST(order_delivered_customer_date AS DATETIME)  AS delivered_date,
    CAST(order_estimated_delivery_date AS DATETIME)  AS estimated_date,
    DATEDIFF(CAST(order_delivered_customer_date AS DATETIME),
             CAST(order_estimated_delivery_date AS DATETIME)) AS delay_days,
    CASE
        WHEN CAST(order_delivered_customer_date AS DATETIME)
           > CAST(order_estimated_delivery_date AS DATETIME) THEN 1
        ELSE 0
    END AS is_late
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;

-- ---------------------------------------------------------------------
-- 5. Overall KPIs (results: 96,470 / 7,826 / 8.11 / 91.89 / 8.9)
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                        AS delivered_orders,
    SUM(is_late)                                    AS late_orders,
    ROUND(100 * SUM(is_late) / COUNT(*), 2)         AS late_percent,
    ROUND(100 - 100 * SUM(is_late) / COUNT(*), 2)   AS on_time_percent,
    ROUND(AVG(CASE WHEN is_late = 1 THEN delay_days END), 1) AS avg_delay_days_when_late
FROM v_delivered_orders;

-- ---------------------------------------------------------------------
-- 6. Late % by customer state (worst first)
-- ---------------------------------------------------------------------
SELECT
    c.customer_state,
    COUNT(*)                                          AS delivered_orders,
    SUM(v.is_late)                                    AS late_orders,
    ROUND(100 * SUM(v.is_late) / COUNT(*), 2)         AS late_percent,
    ROUND(AVG(DATEDIFF(v.delivered_date, v.purchase_date)), 1) AS avg_delivery_days
FROM v_delivered_orders v
JOIN customers c ON v.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY late_percent DESC;

-- ---------------------------------------------------------------------
-- 7. Late % by product category (top 10, categories with 100+ orders)
-- ---------------------------------------------------------------------
SELECT
    t.product_category_name_english AS category,
    COUNT(DISTINCT v.order_id) AS orders,
    COUNT(DISTINCT CASE WHEN v.is_late = 1 THEN v.order_id END) AS late_orders,
    ROUND(100 * COUNT(DISTINCT CASE WHEN v.is_late = 1 THEN v.order_id END)
          / COUNT(DISTINCT v.order_id), 2) AS late_percent
FROM v_delivered_orders v
JOIN order_items i ON v.order_id = i.order_id
JOIN products p ON i.product_id = p.product_id
JOIN product_category_name_translation t
     ON p.product_category_name = t.product_category_name
GROUP BY t.product_category_name_english
HAVING COUNT(DISTINCT v.order_id) >= 100
ORDER BY late_percent DESC
LIMIT 10;

# Which sellers cause the delays

USE deliveriq;

SELECT
    i.seller_id,
    s.seller_state,
    COUNT(DISTINCT v.order_id) AS orders,
    COUNT(DISTINCT CASE WHEN v.is_late = 1 THEN v.order_id END) AS late_orders,
    ROUND(100 * COUNT(DISTINCT CASE WHEN v.is_late = 1 THEN v.order_id END)
          / COUNT(DISTINCT v.order_id), 2) AS late_percent
FROM v_delivered_orders v
JOIN order_items i ON v.order_id = i.order_id
JOIN sellers s ON i.seller_id = s.seller_id
GROUP BY i.seller_id, s.seller_state
HAVING COUNT(DISTINCT v.order_id) >= 50
ORDER BY late_percent DESC
LIMIT 10;

# It rewrites the rule that decides “late” or “on time” in your saved view v_delivered_orders.
USE deliveriq;

CREATE OR REPLACE VIEW v_delivered_orders AS
SELECT
    order_id,
    customer_id,
    CAST(order_purchase_timestamp AS DATETIME)       AS purchase_date,
    CAST(order_delivered_customer_date AS DATETIME)  AS delivered_date,
    CAST(order_estimated_delivery_date AS DATETIME)  AS estimated_date,
    DATEDIFF(CAST(order_delivered_customer_date AS DATETIME),
             CAST(order_estimated_delivery_date AS DATETIME)) AS delay_days,
    CASE
        WHEN DATEDIFF(CAST(order_delivered_customer_date AS DATETIME),
                      CAST(order_estimated_delivery_date AS DATETIME)) > 0 THEN 1
        ELSE 0
    END AS is_late
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;
  
  select * from v_delivered_orders;
  
  # count of drliver and late order with late percent
  USE deliveriq;

SELECT
    COUNT(*)                                        AS delivered_orders,
    SUM(is_late)                                    AS late_orders,
    ROUND(100 * SUM(is_late) / COUNT(*), 2)         AS late_percent,
    ROUND(100 - 100 * SUM(is_late) / COUNT(*), 2)   AS on_time_percent,
    ROUND(AVG(CASE WHEN is_late = 1 THEN delay_days END), 1) AS avg_delay_days_when_late
FROM v_delivered_orders;


USE deliveriq;

CREATE OR REPLACE VIEW v_dashboard_orders AS
SELECT
    v.order_id,
    v.purchase_date,
    v.delivered_date,
    v.estimated_date,
    v.delay_days,
    v.is_late,
    c.customer_state,
    c.customer_city,
    r.review_score,
    p.order_value
FROM v_delivered_orders v
JOIN customers c ON v.customer_id = c.customer_id
LEFT JOIN (SELECT order_id, AVG(review_score) AS review_score
           FROM order_reviews GROUP BY order_id) r ON v.order_id = r.order_id
LEFT JOIN (SELECT order_id, SUM(price + freight_value) AS order_value
           FROM order_items GROUP BY order_id) p ON v.order_id = p.order_id;
  
  SELECT
    COUNT(*)                                          AS orders,
    ROUND(SUM(order_value))                           AS total_order_value,
    ROUND(SUM(CASE WHEN is_late = 1 THEN order_value END)) AS late_order_value
FROM v_dashboard_orders;