-- =====================================================================
-- 06_views_and_explain.sql  |  Views, materialized view, EXPLAIN
-- =====================================================================
SET search_path TO retail;

-- Standard view: denormalised "flat" view over the star schema
CREATE OR REPLACE VIEW v_sales_flat AS
SELECT f.sales_key, f.order_id, d.full_date, d.year_month, d.year_num, d.quarter_num,
       c.customer_name, c.segment, c.region AS customer_region,
       p.product_name, p.category, p.sub_category,
       s.store_name, s.region AS store_region,
       f.quantity, f.discount_pct, f.sales_amount, f.cost_amount,
       f.sales_amount - f.cost_amount AS profit
FROM fact_sales f
JOIN dim_date d     USING (date_key)
JOIN dim_customer c USING (customer_key)
JOIN dim_product p  USING (product_key)
JOIN dim_store s    USING (store_key);

-- Materialized view: pre-computed MoM report (refresh after loads)
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_growth;
CREATE MATERIALIZED VIEW mv_monthly_growth AS
WITH m AS (
    SELECT year_month, SUM(sales_amount) AS revenue, SUM(profit) AS profit
    FROM v_sales_flat GROUP BY year_month
)
SELECT year_month, ROUND(revenue,2) AS revenue, ROUND(profit,2) AS profit,
       ROUND(100.0*(revenue - LAG(revenue) OVER (ORDER BY year_month))
             / NULLIF(LAG(revenue) OVER (ORDER BY year_month),0),2) AS mom_growth_pct
FROM m;
CREATE UNIQUE INDEX ON mv_monthly_growth(year_month);   -- enables REFRESH ... CONCURRENTLY

SELECT * FROM mv_monthly_growth ORDER BY year_month;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_growth;

-- ---------------------------------------------------------------------
-- EXPLAIN optimisation demo: filter on a date range + category
-- ---------------------------------------------------------------------
-- BEFORE: drop the FK index and look at the plan (Seq Scan on fact_sales)
DROP INDEX IF EXISTS idx_fact_date;
EXPLAIN (ANALYZE, BUFFERS)
SELECT SUM(f.sales_amount)
FROM fact_sales f
WHERE f.date_key BETWEEN 20250101 AND 20250131;

-- AFTER: recreate the index and compare cost / actual time
CREATE INDEX idx_fact_date ON fact_sales(date_key);
ANALYZE fact_sales;
EXPLAIN (ANALYZE, BUFFERS)
SELECT SUM(f.sales_amount)
FROM fact_sales f
WHERE f.date_key BETWEEN 20250101 AND 20250131;

-- Star-join plan: check the join order & join methods
EXPLAIN (ANALYZE)
SELECT p.category, SUM(f.sales_amount)
FROM fact_sales f
JOIN dim_product p USING (product_key)
JOIN dim_date d    USING (date_key)
WHERE d.year_num = 2025
GROUP BY p.category;
