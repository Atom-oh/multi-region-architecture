CREATE TABLE sellers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(50),
    status VARCHAR(50) DEFAULT 'PENDING',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE seller_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID REFERENCES sellers(id),
    product_id VARCHAR(255),
    sku VARCHAR(255) NOT NULL,
    price DECIMAL(12,2) NOT NULL,
    stock INTEGER DEFAULT 0,
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_sellers_email ON sellers(email);
CREATE INDEX idx_sellers_status ON sellers(status);
CREATE INDEX idx_seller_products_seller_id ON seller_products(seller_id);
CREATE INDEX idx_seller_products_sku ON seller_products(sku);
