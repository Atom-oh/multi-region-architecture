CREATE TABLE inventory (
    sku VARCHAR(255) PRIMARY KEY,
    available INTEGER NOT NULL DEFAULT 0,
    reserved INTEGER NOT NULL DEFAULT 0,
    total INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_inventory_sku ON inventory(sku);
