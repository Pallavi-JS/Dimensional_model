-- =====================================================================
-- 01_schema.sql  |  Retail Sales Star Schema (PostgreSQL 14+)
-- Fact: fact_sales        Dimensions: dim_date, dim_customer,
--                                     dim_product, dim_store
-- Grain of the fact table: ONE ROW PER PRODUCT LINE ON A SALES ORDER
-- =====================================================================
DROP SCHEMA IF EXISTS retail CASCADE;
CREATE SCHEMA retail;
SET search_path TO retail;

CREATE TABLE dim_date (
    date_key      INT PRIMARY KEY,              -- surrogate key, YYYYMMDD
    full_date     DATE        NOT NULL UNIQUE,
    day_of_month  SMALLINT    NOT NULL,
    day_name      VARCHAR(10) NOT NULL,
    week_of_year  SMALLINT    NOT NULL,
    month_num     SMALLINT    NOT NULL CHECK (month_num BETWEEN 1 AND 12),
    month_name    VARCHAR(10) NOT NULL,
    year_month    CHAR(7)     NOT NULL,         -- e.g. 2024-03
    quarter_num   SMALLINT    NOT NULL CHECK (quarter_num BETWEEN 1 AND 4),
    year_num      SMALLINT    NOT NULL,
    is_weekend    BOOLEAN     NOT NULL
);

CREATE TABLE dim_customer (
    customer_key  SERIAL PRIMARY KEY,
    customer_name VARCHAR(60) NOT NULL,
    segment       VARCHAR(20) NOT NULL CHECK (segment IN ('Consumer','Corporate','Home Office')),
    city          VARCHAR(40) NOT NULL,
    state         VARCHAR(40) NOT NULL,
    region        VARCHAR(20) NOT NULL
);

CREATE TABLE dim_product (
    product_key   SERIAL PRIMARY KEY,
    product_name  VARCHAR(60)   NOT NULL,
    category      VARCHAR(30)   NOT NULL,
    sub_category  VARCHAR(30)   NOT NULL,
    brand         VARCHAR(30)   NOT NULL,
    unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    unit_cost     NUMERIC(10,2) NOT NULL CHECK (unit_cost  > 0)
);

CREATE TABLE dim_store (
    store_key     SERIAL PRIMARY KEY,
    store_name    VARCHAR(40) NOT NULL,
    city          VARCHAR(40) NOT NULL,
    region        VARCHAR(20) NOT NULL
);

CREATE TABLE fact_sales (
    sales_key     BIGSERIAL PRIMARY KEY,
    order_id      INT          NOT NULL,
    date_key      INT          NOT NULL REFERENCES dim_date(date_key),
    customer_key  INT          NOT NULL REFERENCES dim_customer(customer_key),
    product_key   INT          NOT NULL REFERENCES dim_product(product_key),
    store_key     INT          NOT NULL REFERENCES dim_store(store_key),
    quantity      INT          NOT NULL CHECK (quantity > 0),
    discount_pct  NUMERIC(4,2) NOT NULL DEFAULT 0 CHECK (discount_pct BETWEEN 0 AND 0.5),
    sales_amount  NUMERIC(12,2) NOT NULL,       -- revenue after discount
    cost_amount   NUMERIC(12,2) NOT NULL
);

-- FK columns are the join path for every report, so index them
CREATE INDEX idx_fact_date     ON fact_sales(date_key);
CREATE INDEX idx_fact_customer ON fact_sales(customer_key);
CREATE INDEX idx_fact_product  ON fact_sales(product_key);
CREATE INDEX idx_fact_store    ON fact_sales(store_key);
