-- =====================================================================
-- 05_rollup_cube_grouping_sets.sql  |  Multi-level aggregation
-- =====================================================================
SET search_path TO retail;

-- Q1. ROLLUP: year -> quarter subtotals + grand total
SELECT COALESCE(year_num::TEXT,'ALL YEARS')    AS year,
       COALESCE(quarter_num::TEXT,'ALL QTRS')  AS quarter,
       ROUND(SUM(sales_amount),0)              AS revenue,
       GROUPING(year_num, quarter_num)         AS grp_level
FROM fact_sales f JOIN dim_date d USING (date_key)
GROUP BY ROLLUP (year_num, quarter_num)
ORDER BY year_num NULLS LAST, quarter_num NULLS LAST;

-- Q2. ROLLUP over category -> sub_category
SELECT COALESCE(category,'** TOTAL **')         AS category,
       COALESCE(sub_category,'-- subtotal --')  AS sub_category,
       ROUND(SUM(sales_amount),0) AS revenue,
       ROUND(SUM(sales_amount - cost_amount),0) AS profit
FROM fact_sales f JOIN dim_product p USING (product_key)
GROUP BY ROLLUP (category, sub_category)
ORDER BY category NULLS LAST, sub_category NULLS LAST;

-- Q3. CUBE: every combination of region x segment
SELECT COALESCE(s.region,'ALL')  AS store_region,
       COALESCE(c.segment,'ALL') AS segment,
       ROUND(SUM(f.sales_amount),0) AS revenue
FROM fact_sales f
JOIN dim_store s    USING (store_key)
JOIN dim_customer c USING (customer_key)
GROUP BY CUBE (s.region, c.segment)
ORDER BY s.region NULLS LAST, c.segment NULLS LAST;

-- Q4. GROUPING SETS: only the aggregations we want in a single scan
SELECT d.year_num, p.category, s.region,
       ROUND(SUM(f.sales_amount),0) AS revenue
FROM fact_sales f
JOIN dim_date d    USING (date_key)
JOIN dim_product p USING (product_key)
JOIN dim_store s   USING (store_key)
GROUP BY GROUPING SETS ((d.year_num, p.category), (d.year_num, s.region), ())
ORDER BY d.year_num NULLS LAST, p.category NULLS LAST, s.region NULLS LAST;
