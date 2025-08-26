INSERT INTO users (email, first_name, last_name) VALUES
('john.doe@example.com', 'John', 'Doe'),
('jane.smith@example.com', 'Jane', 'Smith'),
('bob.johnson@example.com', 'Bob', 'Johnson');

INSERT INTO products (name, description, price, stock_quantity, category) VALUES
('Laptop', 'High-performance laptop', 999.99, 50, 'Electronics'),
('Smartphone', 'Latest smartphone model', 699.99, 100, 'Electronics'),
('Book', 'Programming guide', 49.99, 200, 'Books'),
('Headphones', 'Wireless headphones', 199.99, 75, 'Electronics');

INSERT INTO orders (user_id, status, total_amount, shipping_address) VALUES
(1, 'pending', 999.99, '123 Main St, City, State'),
(2, 'processing', 749.98, '456 Oak Ave, City, State'),
(3, 'shipped', 49.99, '789 Pine Rd, City, State');

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 999.99),
(2, 2, 1, 699.99),
(2, 4, 1, 49.99),
(3, 3, 1, 49.99);