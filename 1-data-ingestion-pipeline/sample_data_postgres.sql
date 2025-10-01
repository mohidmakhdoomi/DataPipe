INSERT INTO users (email, first_name, last_name) VALUES
('john.doe@example.com', 'John', 'Doe'),
('jane.smith@example.com', 'Jane', 'Smith'),
('bob.johnson@example.com', 'Bob', 'Johnson'),
('rocky.balboa@example.com', 'rocky', 'balboa'),
('johnny.dang@example.com', 'johnny', 'dang'),
('johnny.bravo@example.com', 'johnny', 'bravo'),
('john.cena@example.com', 'john', 'cena'),
('john.lennon@example.com', 'john', 'lennon'),
('johnny.ives@example.com', 'johnny', 'ives'),
('john.gotti@example.com', 'john', 'gotti'),
('bruce.wayne@example.com', 'bruce', 'wayne'),
('not.bruce.wayne@example.com', 'bat', 'man'),
('leonardo.dicaprio@example.com', 'leonardo', 'dicaprio'),
('leonardo.divinci@example.com', 'leonardo', 'divinci');

INSERT INTO users (email, first_name, last_name) 
SELECT
    'user' || subquery.uuid || '@example.com',
    'User' || subquery.uuid,
    'Test' || subquery.uuid
    FROM (SELECT generate_series(15, 9000) as uuid) AS subquery;

INSERT INTO products (name, description, price, stock_quantity, category) VALUES
('Laptop', 'High-performance laptop', 999.99, 50, 'Electronics'),
('Smartphone', 'Latest smartphone model', 699.99, 100, 'Electronics'),
('Book', 'Programming guide', 49.99, 200, 'Books'),
('Headphones', 'Wireless headphones', 199.99, 75, 'Electronics');

INSERT INTO products (name, description, price, stock_quantity, category)
SELECT
    'name' || subquery.uuid,
    'description' || subquery.uuid,
    subquery.uuid,
    subquery.uuid*100,
    'category' || subquery.uuid
    FROM (SELECT generate_series(5, 9000) as uuid) AS subquery;

INSERT INTO orders (user_id, status, total_amount, shipping_address) VALUES
(1, 'pending', 999.99, '123 Main St, City, State'),
(2, 'processing', 749.98, '456 Oak Ave, City, State'),
(3, 'shipped', 49.99, '789 Pine Rd, City, State');

INSERT INTO orders (user_id, status, total_amount, shipping_address)
SELECT
    subquery.uuid,
    (array['pending', 'processing', 'shipped', 'delivered', 'cancelled'])[floor(random() * 5 + 1)],
    subquery.uuid*100,
    'shipping_address' || subquery.uuid
    FROM (SELECT generate_series(4, 9000) as uuid) AS subquery;

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 999.99),
(2, 2, 1, 699.99),
(2, 4, 1, 49.99),
(3, 3, 1, 49.99);

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT
    subquery.uuid,
    subquery.uuid,
    (array[1, 5, 42, 21, 7])[floor(random() * 5 + 1)],
    subquery.uuid*100
    FROM (SELECT generate_series(5, 9000) as uuid) AS subquery;