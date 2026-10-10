-- =====================================================================
-- 04_cte_mom_growth.sql  |  Month-over-Month growth with CTEs
-- =====================================================================
SET search_path TO retail;

-- Q1. Overall MoM revenue growth (chained CTEs: aggregate -> LAG -> growth %)
WITH monthly_sales AS (
    SELECT d.year_month, SUM(f.sales_amount) AS revenue
    FROM fact_sales f JOIN dim_date d USING (date_key)
    GROUP BY d.year_month
),
with_prev AS (
    SELECT year_month, revenue,
           LAG(revenue) OVER (ORDER BY year_month) AS prev_revenue
    FROM monthly_sales
)
SELECT year_month,
       ROUND(revenue,2)                                   AS revenue,
       ROUND(prev_revenue,2)                              AS prev_month_revenue,
       ROUND(revenue - prev_revenue,2)                    AS abs_change,
       ROUND(100.0 * (revenue - prev_revenue) / NULLIF(prev_revenue,0),2) AS mom_growth_pct,
       CASE WHEN prev_revenue IS NULL THEN 'n/a'
            WHEN revenue > prev_revenue THEN 'UP'
            WHEN revenue < prev_revenue THEN 'DOWN' ELSE 'FLAT' END AS trend
FROM with_prev
ORDER BY year_month;

-- Q2. MoM growth by product category (partitioned LAG)
WITH cat_month AS (
    SELECT p.category, d.year_month, SUM(f.sales_amount) AS revenue
    FROM fact_sales f
    JOIN dim_date d    USING (date_key)
    JOIN dim_product p USING (product_key)
    GROUP BY p.category, d.year_month
)
SELECT category, year_month, ROUND(revenue,0) AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (PARTITION BY category ORDER BY year_month))
             / NULLIF(LAG(revenue) OVER (PARTITION BY category ORDER BY year_month),0),2) AS mom_growth_pct
FROM cat_month
ORDER BY category, year_month;

-- Q3. Year-over-year for the same month (LAG with offset 12) + MoM side by side
WITH m AS (
    SELECT d.year_month, SUM(f.sales_amount) AS revenue
    FROM fact_sales f JOIN dim_date d USING (date_key) GROUP BY d.year_month
)
SELECT year_month, ROUND(revenue,0) AS revenue,
       ROUND(100.0*(revenue - LAG(revenue,1)  OVER (ORDER BY year_month)) / NULLIF(LAG(revenue,1)  OVER (ORDER BY year_month),0),2) AS mom_pct,
       ROUND(100.0*(revenue - LAG(revenue,12) OVER (ORDER BY year_month)) / NULLIF(LAG(revenue,12) OVER (ORDER BY year_month),0),2) AS yoy_pct
FROM m ORDER BY year_month;

-- Q4. Best and worst growth months (CTE reused twice)
WITH m AS (
    SELECT d.year_month, SUM(f.sales_amount) AS revenue
    FROM fact_sales f JOIN dim_date d USING (date_key) GROUP BY d.year_month
),
g AS (
    SELECT year_month, revenue,
           100.0*(revenue - LAG(revenue) OVER (ORDER BY year_month)) / NULLIF(LAG(revenue) OVER (ORDER BY year_month),0) AS mom_pct
    FROM m
)
(SELECT 'Best 3'  AS bucket, year_month, ROUND(mom_pct,2) AS mom_pct FROM g WHERE mom_pct IS NOT NULL ORDER BY mom_pct DESC LIMIT 3)
UNION ALL
(SELECT 'Worst 3' AS bucket, year_month, ROUND(mom_pct,2) AS mom_pct FROM g WHERE mom_pct IS NOT NULL ORDER BY mom_pct ASC  LIMIT 3);

-- Q5. Region MoM growth, showing only declines (HAVING-style filter in outer query)
WITH rm AS (
    SELECT s.region, d.year_month, SUM(f.sales_amount) AS revenue
    FROM fact_sales f JOIN dim_date d USING (date_key) JOIN dim_store s USING (store_key)
    GROUP BY s.region, d.year_month
),
g AS (
    SELECT region, year_month, revenue,
           100.0*(revenue - LAG(revenue) OVER (PARTITION BY region ORDER BY year_month))
           / NULLIF(LAG(revenue) OVER (PARTITION BY region ORDER BY year_month),0) AS mom_pct
    FROM rm
)
SELECT region, year_month, ROUND(revenue,0) AS revenue, ROUND(mom_pct,2) AS mom_pct
FROM g WHERE mom_pct < -20 ORDER BY mom_pct LIMIT 10;

-- Q6. Recursive CTE: generate a gap-free month calendar and LEFT JOIN sales to it
--     (guarantees months with zero sales still appear)
WITH RECURSIVE months AS (
    SELECT DATE '2024-01-01' AS month_start
    UNION ALL
    SELECT (month_start + INTERVAL '1 month')::DATE FROM months WHERE month_start < DATE '2025-12-01'
),
m AS (
    SELECT to_char(d.full_date,'YYYY-MM') AS year_month, SUM(f.sales_amount) AS revenue
    FROM fact_sales f JOIN dim_date d USING (date_key) GROUP BY 1
)
SELECT to_char(months.month_start,'YYYY-MM') AS year_month,
       COALESCE(ROUND(m.revenue,0),0) AS revenue
FROM months LEFT JOIN m ON m.year_month = to_char(months.month_start,'YYYY-MM')
ORDER BY 1;
