-- =====================================================================
-- 03_window_functions.sql  |  Window function ranking report
-- Covers: ROW_NUMBER, RANK, DENSE_RANK, NTILE, LAG, LEAD,
--         running totals with frames, moving average, FIRST/LAST_VALUE,
--         PERCENT_RANK, SUM() OVER (PARTITION BY) share-of-total
-- =====================================================================
SET search_path TO retail;

-- Q1. RANK vs DENSE_RANK vs ROW_NUMBER: products by revenue within category
SELECT p.category, p.product_name,
       SUM(f.sales_amount)                                           AS revenue,
       ROW_NUMBER() OVER (PARTITION BY p.category ORDER BY SUM(f.sales_amount) DESC) AS row_num,
       RANK()       OVER (PARTITION BY p.category ORDER BY SUM(f.sales_amount) DESC) AS rnk,
       DENSE_RANK() OVER (PARTITION BY p.category ORDER BY SUM(f.sales_amount) DESC) AS dense_rnk
FROM fact_sales f JOIN dim_product p USING (product_key)
GROUP BY p.category, p.product_name
ORDER BY p.category, rnk;

-- Q2. Top 3 products per category (filter on a window result needs a CTE/subquery)
WITH ranked AS (
    SELECT p.category, p.product_name, SUM(f.sales_amount) AS revenue,
           RANK() OVER (PARTITION BY p.category ORDER BY SUM(f.sales_amount) DESC) AS rnk
    FROM fact_sales f JOIN dim_product p USING (product_key)
    GROUP BY p.category, p.product_name
)
SELECT * FROM ranked WHERE rnk <= 3 ORDER BY category, rnk;

-- Q3. Top 5 customers overall + their share of total revenue
SELECT c.customer_name, c.segment,
       SUM(f.sales_amount) AS revenue,
       ROUND(100 * SUM(f.sales_amount) / SUM(SUM(f.sales_amount)) OVER (), 2) AS pct_of_total,
       DENSE_RANK() OVER (ORDER BY SUM(f.sales_amount) DESC) AS customer_rank
FROM fact_sales f JOIN dim_customer c USING (customer_key)
GROUP BY c.customer_name, c.segment
ORDER BY customer_rank
LIMIT 5;

-- Q4. NTILE: customer spend quartiles (1 = top spenders)
WITH spend AS (
    SELECT customer_key, SUM(sales_amount) AS total_spend FROM fact_sales GROUP BY customer_key
), tiled AS (
    SELECT customer_key, total_spend, NTILE(4) OVER (ORDER BY total_spend DESC) AS spend_quartile
    FROM spend
)
SELECT spend_quartile, COUNT(*) AS customers,
       ROUND(MIN(total_spend),0) AS min_spend, ROUND(MAX(total_spend),0) AS max_spend
FROM tiled GROUP BY spend_quartile ORDER BY spend_quartile;

-- Q5. LAG / LEAD: month-by-month revenue with previous & next month
WITH monthly AS (
    SELECT d.year_month, SUM(f.sales_amount) AS revenue
    FROM fact_sales f JOIN dim_date d USING (date_key)
    GROUP BY d.year_month
)
SELECT year_month, ROUND(revenue,0) AS revenue,
       ROUND(LAG(revenue)  OVER (ORDER BY year_month),0) AS prev_month,
       ROUND(LEAD(revenue) OVER (ORDER BY year_month),0) AS next_month
FROM monthly ORDER BY year_month;

-- Q6. Running total (frame: UNBOUNDED PRECEDING -> CURRENT ROW) per year
WITH monthly AS (
    SELECT d.year_num, d.year_month, SUM(f.sales_amount) AS revenue
    FROM fact_sales f JOIN dim_date d USING (date_key)
    GROUP BY d.year_num, d.year_month
)
SELECT year_num, year_month, ROUND(revenue,0) AS revenue,
       ROUND(SUM(revenue) OVER (PARTITION BY year_num ORDER BY year_month
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),0) AS ytd_revenue
FROM monthly ORDER BY year_month;

-- Q7. 3-month moving average (frame: 2 PRECEDING -> CURRENT ROW)
WITH monthly AS (
    SELECT d.year_month, SUM(f.sales_amount) AS revenue
    FROM fact_sales f JOIN dim_date d USING (date_key) GROUP BY d.year_month
)
SELECT year_month, ROUND(revenue,0) AS revenue,
       ROUND(AVG(revenue) OVER (ORDER BY year_month
             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),0) AS moving_avg_3m
FROM monthly ORDER BY year_month;

-- Q8. Best and worst month per year (FIRST_VALUE / LAST_VALUE need a full frame!)
WITH monthly AS (
    SELECT d.year_num, d.year_month, SUM(f.sales_amount) AS revenue
    FROM fact_sales f JOIN dim_date d USING (date_key) GROUP BY d.year_num, d.year_month
)
SELECT DISTINCT year_num,
       FIRST_VALUE(year_month) OVER w AS best_month,
       FIRST_VALUE(ROUND(revenue,0)) OVER w AS best_revenue,
       LAST_VALUE(year_month)  OVER w AS worst_month,
       LAST_VALUE(ROUND(revenue,0))  OVER w AS worst_revenue
FROM monthly
WINDOW w AS (PARTITION BY year_num ORDER BY revenue DESC
             ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
ORDER BY year_num;

-- Q9. Top store per region (rank within region) + gap to #1
WITH store_rev AS (
    SELECT s.region, s.store_name, SUM(f.sales_amount) AS revenue
    FROM fact_sales f JOIN dim_store s USING (store_key)
    GROUP BY s.region, s.store_name
)
SELECT region, store_name, ROUND(revenue,0) AS revenue,
       RANK() OVER (PARTITION BY region ORDER BY revenue DESC) AS rank_in_region,
       ROUND(MAX(revenue) OVER (PARTITION BY region) - revenue,0) AS gap_to_leader
FROM store_rev ORDER BY region, rank_in_region;

-- Q10. PERCENT_RANK + CUME_DIST of products by units sold
SELECT p.product_name, SUM(f.quantity) AS units,
       ROUND(PERCENT_RANK() OVER (ORDER BY SUM(f.quantity))::NUMERIC,2) AS pct_rank,
       ROUND(CUME_DIST()    OVER (ORDER BY SUM(f.quantity))::NUMERIC,2) AS cume_dist
FROM fact_sales f JOIN dim_product p USING (product_key)
GROUP BY p.product_name ORDER BY units DESC LIMIT 10;

-- Q11. Customer's repeat-purchase gap: days since their previous order line
WITH cust_orders AS (
    SELECT f.customer_key, d.full_date,
           LAG(d.full_date) OVER (PARTITION BY f.customer_key ORDER BY d.full_date, f.sales_key) AS prev_date
    FROM fact_sales f JOIN dim_date d USING (date_key)
)
SELECT customer_key, ROUND(AVG(full_date - prev_date),1) AS avg_days_between_purchases
FROM cust_orders WHERE prev_date IS NOT NULL
GROUP BY customer_key ORDER BY avg_days_between_purchases LIMIT 10;
