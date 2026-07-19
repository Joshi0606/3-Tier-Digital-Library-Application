-- ============================================================
-- schema.sql
-- Initialises the digital_library database.
-- Docker Compose mounts this into MySQL's initdb directory
-- so it runs automatically on first container start.
-- ============================================================

CREATE DATABASE IF NOT EXISTS digital_library;
USE digital_library;

-- Users table — stores signup/login credentials
CREATE TABLE IF NOT EXISTS users (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100)  NOT NULL,
    email      VARCHAR(255)  UNIQUE NOT NULL,
    password   VARCHAR(255)  NOT NULL,          -- stored as bcrypt hash
    created_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

-- Books table — library catalogue
CREATE TABLE IF NOT EXISTS books (
    id     INT AUTO_INCREMENT PRIMARY KEY,
    title  VARCHAR(200) NOT NULL,
    author VARCHAR(100) NOT NULL
);

-- Borrow records — tracks which user borrowed which book
-- Unique constraint prevents borrowing the same book twice
CREATE TABLE IF NOT EXISTS borrow_records (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    user_id     INT NOT NULL,
    book_id     INT NOT NULL,
    borrow_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_borrow (user_id, book_id),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (book_id) REFERENCES books(id)
);

-- Seed some books so the UI has data to display immediately
INSERT IGNORE INTO books (title, author) VALUES
    ('The Pragmatic Programmer', 'David Thomas'),
    ('Clean Code',               'Robert C. Martin'),
    ('Designing Data-Intensive Applications', 'Martin Kleppmann'),
    ('The Phoenix Project',      'Gene Kim'),
    ('Kubernetes in Action',     'Marko Luksa');
