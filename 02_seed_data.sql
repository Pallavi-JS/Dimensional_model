-- =====================================================================
-- 02_seed_data.sql  |  Deterministic sample data (setseed => repeatable)
-- Produces: 731 dates, 120 customers, 24 products, 6 stores, ~6000 sales
-- =====================================================================
SET search_path TO retail;
SELECT setseed(0.42);

-- ---------- dim_date : 2024-01-01 .. 2025-12-31 ----------
INSERT INTO dim_date
SELECT to_char(d,'YYYYMMDD')::INT,
       d::DATE,
       EXTRACT(DAY FROM d),
       trim(to_char(d,'Day')),
       EXTRACT(WEEK FROM d),
       EXTRACT(MONTH FROM d),
       trim(to_char(d,'Month')),
       to_char(d,'YYYY-MM'),
       EXTRACT(QUARTER FROM d),
       EXTRACT(YEAR FROM d),
       EXTRACT(ISODOW FROM d) IN (6,7)
FROM generate_series('2024-01-01'::DATE,'2025-12-31'::DATE,'1 day') AS d;

-- ---------- dim_store ----------
INSERT INTO dim_store (store_name, city, region) VALUES
 ('Mumbai Central','Mumbai','West'),   ('Pune Camp','Pune','West'),
 ('Delhi Connaught','Delhi','North'),  ('Chandigarh Sec17','Chandigarh','North'),
 ('Bengaluru MG Road','Bengaluru','South'), ('Chennai T Nagar','Chennai','South');

-- ---------- dim_product ----------
INSERT INTO dim_product (product_name, category, sub_category, brand, unit_price, unit_cost) VALUES
 ('Laptop Pro 14',      'Technology','Computers',  'Zenith',  85000, 68000),
 ('Laptop Air 13',      'Technology','Computers',  'Zenith',  62000, 49000),
 ('Smartphone X',       'Technology','Phones',     'Nova',    45000, 34000),
 ('Smartphone Lite',    'Technology','Phones',     'Nova',    18000, 13500),
 ('Wireless Earbuds',   'Technology','Accessories','Nova',     4500,  2800),
 ('USB-C Hub',          'Technology','Accessories','Zenith',   2200,  1200),
 ('Office Chair Ergo',  'Furniture', 'Chairs',     'Sitwell', 12500,  8200),
 ('Gaming Chair',       'Furniture', 'Chairs',     'Sitwell', 15500, 10400),
 ('Standing Desk',      'Furniture', 'Tables',     'Woodcraft',28000,19000),
 ('Study Table',        'Furniture', 'Tables',     'Woodcraft', 9000, 5800),
 ('Bookcase 5-Shelf',   'Furniture', 'Storage',    'Woodcraft', 7500, 4900),
 ('Floor Lamp',         'Furniture', 'Decor',      'Lumina',    3200, 1800),
 ('A4 Paper Ream',      'Office Supplies','Paper',     'PaperPlus',  350,  220),
 ('Spiral Notebook',    'Office Supplies','Paper',     'PaperPlus',  120,   60),
 ('Gel Pen Box',        'Office Supplies','Art',       'InkWell',    250,  130),
 ('Marker Set',         'Office Supplies','Art',       'InkWell',    480,  260),
 ('Stapler Heavy',      'Office Supplies','Fasteners', 'BindIt',     650,  380),
 ('Binder Clips 50pk',  'Office Supplies','Fasteners', 'BindIt',     180,   90),
 ('Filing Cabinet',     'Office Supplies','Storage',   'BindIt',    6800, 4600),
 ('Whiteboard 4x3',     'Office Supplies','Storage',   'InkWell',   3900, 2500),
 ('Coffee Machine',     'Technology','Appliances', 'Brewly',    8500,  5600),
 ('Water Purifier',     'Technology','Appliances', 'Brewly',   14500,  9800),
 ('Monitor 27in',       'Technology','Computers',  'Zenith',   21000, 15500),
 ('Mechanical Keyboard','Technology','Accessories','Nova',      5200,  3100);

-- ---------- dim_customer : 120 synthetic customers ----------
WITH loc(city,state,region) AS (VALUES
  ('Mumbai','Maharashtra','West'),('Pune','Maharashtra','West'),
  ('Delhi','Delhi','North'),('Chandigarh','Punjab','North'),
  ('Bengaluru','Karnataka','South'),('Chennai','Tamil Nadu','South'),
  ('Kolkata','West Bengal','East'),('Bhubaneswar','Odisha','East'))
INSERT INTO dim_customer (customer_name, segment, city, state, region)
SELECT 'Customer ' || lpad(g::TEXT,3,'0'),
       (ARRAY['Consumer','Consumer','Corporate','Home Office'])[1 + floor(random()*4)::INT],
       l.city, l.state, l.region
FROM generate_series(1,120) g
JOIN LATERAL (SELECT * FROM loc OFFSET ((g*7) % 8) LIMIT 1) l ON TRUE;

-- ---------- fact_sales : ~6000 order lines ----------
-- Seasonality: Oct-Dec uplift, Jan-Feb dip,.
WITH raw AS (
    SELECT g AS order_id,
           to_char(DATE '2024-01-01' + floor(random()*731)::INT, 'YYYYMMDD')::INT AS date_key,
           1 + floor(random()*120)::INT AS customer_key,
           1 + floor(random()*24)::INT  AS product_key,
           1 + floor(random()*6)::INT   AS store_key,
           1 + floor(random()*4)::INT   AS quantity,
           (ARRAY[0,0,0,0.05,0.10,0.15])[1 + floor(random()*6)::INT]::NUMERIC(4,2) AS discount_pct
    FROM generate_series(1,6000) g
)
INSERT INTO fact_sales (order_id,date_key,customer_key,product_key,store_key,quantity,discount_pct,sales_amount,cost_amount)
SELECT r.order_id, r.date_key, r.customer_key, r.product_key, r.store_key, r.quantity, r.discount_pct,
       ROUND(p.unit_price * r.quantity * (1 - r.discount_pct), 2),
       ROUND(p.unit_cost  * r.quantity, 2)
FROM raw r JOIN dim_product p USING (product_key)
-- seasonality filter: keep all Q4 rows, 70% of Jan/Feb rows, 85% of others
WHERE random() < CASE
        WHEN substr(r.date_key::TEXT,5,2) IN ('10','11','12') THEN 1.0
        WHEN substr(r.date_key::TEXT,5,2) IN ('01','02')      THEN 0.7
        ELSE 0.85 END;

ANALYZE;
