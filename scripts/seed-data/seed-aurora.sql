-- ============================================================================
-- Multi-Region Shopping Mall - Aurora PostgreSQL Seed Data
-- Services: user-account, order, payment, inventory
-- ============================================================================

-- Users (50)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE NOT NULL,
  username VARCHAR(100) NOT NULL,
  password_hash VARCHAR(255) NOT NULL DEFAULT '$2b$12$LJ3m4ys5RGjZVGQrFGMpAODvyhRGIRJ7S4sFPsIzMGGr7kMd8H2s2',
  full_name VARCHAR(200),
  phone VARCHAR(20),
  status VARCHAR(20) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO users (id, email, username, full_name, phone, status) VALUES
('a0000001-0000-0000-0000-000000000001', 'kim.minjun@gmail.com', 'minjun_kim', '김민준', '010-1234-5678', 'active'),
('a0000001-0000-0000-0000-000000000002', 'lee.soyeon@naver.com', 'soyeon_lee', '이소연', '010-2345-6789', 'active'),
('a0000001-0000-0000-0000-000000000003', 'park.jihoon@kakao.com', 'jihoon_park', '박지훈', '010-3456-7890', 'active'),
('a0000001-0000-0000-0000-000000000004', 'choi.yuna@gmail.com', 'yuna_choi', '최유나', '010-4567-8901', 'active'),
('a0000001-0000-0000-0000-000000000005', 'jung.doyeon@naver.com', 'doyeon_jung', '정도연', '010-5678-9012', 'active'),
('a0000001-0000-0000-0000-000000000006', 'kang.siwoo@gmail.com', 'siwoo_kang', '강시우', '010-6789-0123', 'active'),
('a0000001-0000-0000-0000-000000000007', 'yoon.haeun@kakao.com', 'haeun_yoon', '윤하은', '010-7890-1234', 'active'),
('a0000001-0000-0000-0000-000000000008', 'shin.jiwon@naver.com', 'jiwon_shin', '신지원', '010-8901-2345', 'active'),
('a0000001-0000-0000-0000-000000000009', 'han.seojun@gmail.com', 'seojun_han', '한서준', '010-9012-3456', 'active'),
('a0000001-0000-0000-0000-000000000010', 'oh.minji@kakao.com', 'minji_oh', '오민지', '010-0123-4567', 'active'),
('a0000001-0000-0000-0000-000000000011', 'seo.junhyuk@gmail.com', 'junhyuk_seo', '서준혁', '010-1111-2222', 'active'),
('a0000001-0000-0000-0000-000000000012', 'kwon.subin@naver.com', 'subin_kwon', '권수빈', '010-2222-3333', 'active'),
('a0000001-0000-0000-0000-000000000013', 'lim.taeyang@kakao.com', 'taeyang_lim', '임태양', '010-3333-4444', 'active'),
('a0000001-0000-0000-0000-000000000014', 'song.eunji@gmail.com', 'eunji_song', '송은지', '010-4444-5555', 'active'),
('a0000001-0000-0000-0000-000000000015', 'baek.hyunwoo@naver.com', 'hyunwoo_baek', '백현우', '010-5555-6666', 'active'),
('a0000001-0000-0000-0000-000000000016', 'jang.nayeon@kakao.com', 'nayeon_jang', '장나연', '010-6666-7777', 'active'),
('a0000001-0000-0000-0000-000000000017', 'hwang.donghyun@gmail.com', 'donghyun_hwang', '황동현', '010-7777-8888', 'active'),
('a0000001-0000-0000-0000-000000000018', 'ahn.chaewon@naver.com', 'chaewon_ahn', '안채원', '010-8888-9999', 'active'),
('a0000001-0000-0000-0000-000000000019', 'yu.sangmin@kakao.com', 'sangmin_yu', '유상민', '010-9999-0000', 'active'),
('a0000001-0000-0000-0000-000000000020', 'no.jiyoung@gmail.com', 'jiyoung_no', '노지영', '010-1010-2020', 'active'),
('a0000001-0000-0000-0000-000000000021', 'moon.haejin@naver.com', 'haejin_moon', '문해진', '010-2020-3030', 'active'),
('a0000001-0000-0000-0000-000000000022', 'ko.yeonsu@kakao.com', 'yeonsu_ko', '고연수', '010-3030-4040', 'active'),
('a0000001-0000-0000-0000-000000000023', 'hong.gunwoo@gmail.com', 'gunwoo_hong', '홍건우', '010-4040-5050', 'active'),
('a0000001-0000-0000-0000-000000000024', 'bae.sooyoung@naver.com', 'sooyoung_bae', '배수영', '010-5050-6060', 'active'),
('a0000001-0000-0000-0000-000000000025', 'cho.minseo@kakao.com', 'minseo_cho', '조민서', '010-6060-7070', 'active'),
('a0000001-0000-0000-0000-000000000026', 'nam.woojin@gmail.com', 'woojin_nam', '남우진', '010-7070-8080', 'active'),
('a0000001-0000-0000-0000-000000000027', 'yang.hayoung@naver.com', 'hayoung_yang', '양하영', '010-8080-9090', 'active'),
('a0000001-0000-0000-0000-000000000028', 'ryu.jaehyun@kakao.com', 'jaehyun_ryu', '류재현', '010-9090-1010', 'active'),
('a0000001-0000-0000-0000-000000000029', 'ha.jimin@gmail.com', 'jimin_ha', '하지민', '010-1212-3434', 'active'),
('a0000001-0000-0000-0000-000000000030', 'woo.seungho@naver.com', 'seungho_woo', '우승호', '010-2323-4545', 'active'),
('a0000001-0000-0000-0000-000000000031', 'cha.yerin@kakao.com', 'yerin_cha', '차예린', '010-3434-5656', 'active'),
('a0000001-0000-0000-0000-000000000032', 'gong.taehee@gmail.com', 'taehee_gong', '공태희', '010-4545-6767', 'active'),
('a0000001-0000-0000-0000-000000000033', 'min.sungwoo@naver.com', 'sungwoo_min', '민성우', '010-5656-7878', 'active'),
('a0000001-0000-0000-0000-000000000034', 'byun.areum@kakao.com', 'areum_byun', '변아름', '010-6767-8989', 'active'),
('a0000001-0000-0000-0000-000000000035', 'son.jaemin@gmail.com', 'jaemin_son', '손재민', '010-7878-9090', 'active'),
('a0000001-0000-0000-0000-000000000036', 'im.soojin@naver.com', 'soojin_im', '임수진', '010-8989-0101', 'active'),
('a0000001-0000-0000-0000-000000000037', 'pyo.kanghyun@kakao.com', 'kanghyun_pyo', '표강현', '010-0101-1212', 'active'),
('a0000001-0000-0000-0000-000000000038', 'ji.heesun@gmail.com', 'heesun_ji', '지희선', '010-1313-2424', 'active'),
('a0000001-0000-0000-0000-000000000039', 'tak.youngjae@naver.com', 'youngjae_tak', '탁영재', '010-2424-3535', 'active'),
('a0000001-0000-0000-0000-000000000040', 'goo.dahye@kakao.com', 'dahye_goo', '구다혜', '010-3535-4646', 'active'),
('a0000001-0000-0000-0000-000000000041', 'ma.hyunsoo@gmail.com', 'hyunsoo_ma', '마현수', '010-4646-5757', 'active'),
('a0000001-0000-0000-0000-000000000042', 'pi.eunbi@naver.com', 'eunbi_pi', '피은비', '010-5757-6868', 'active'),
('a0000001-0000-0000-0000-000000000043', 'do.wonho@kakao.com', 'wonho_do', '도원호', '010-6868-7979', 'active'),
('a0000001-0000-0000-0000-000000000044', 'ga.suyeon@gmail.com', 'suyeon_ga', '가수연', '010-7979-8080', 'active'),
('a0000001-0000-0000-0000-000000000045', 'sa.junwoo@naver.com', 'junwoo_sa', '사준우', '010-8080-9191', 'active'),
('a0000001-0000-0000-0000-000000000046', 'ta.jihye@kakao.com', 'jihye_ta', '타지혜', '010-9191-0202', 'active'),
('a0000001-0000-0000-0000-000000000047', 'na.chanho@gmail.com', 'chanho_na', '나찬호', '010-0202-1313', 'active'),
('a0000001-0000-0000-0000-000000000048', 'ra.mirae@naver.com', 'mirae_ra', '라미래', '010-1414-2525', 'active'),
('a0000001-0000-0000-0000-000000000049', 'da.yongjun@kakao.com', 'yongjun_da', '다용준', '010-2525-3636', 'active'),
('a0000001-0000-0000-0000-000000000050', 'ba.seonhwa@gmail.com', 'seonhwa_ba', '바선화', '010-3636-4747', 'active')
ON CONFLICT (email) DO NOTHING;

-- Orders (200)
CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  status VARCHAR(30) NOT NULL DEFAULT 'pending',
  total_amount DECIMAL(12,2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'KRW',
  shipping_address JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES orders(id),
  product_id VARCHAR(50) NOT NULL,
  product_name VARCHAR(200),
  quantity INTEGER NOT NULL,
  unit_price DECIMAL(12,2) NOT NULL,
  total_price DECIMAL(12,2) NOT NULL
);

-- Generate 200 orders with various statuses
DO $$
DECLARE
  user_ids UUID[] := ARRAY(SELECT id FROM users ORDER BY id LIMIT 50);
  statuses TEXT[] := ARRAY['pending','confirmed','processing','shipped','delivered','delivered','delivered','cancelled','returned'];
  addresses JSONB[] := ARRAY[
    '{"city":"서울","district":"강남구","street":"테헤란로 152","zipcode":"06236"}'::jsonb,
    '{"city":"서울","district":"마포구","street":"월드컵북로 396","zipcode":"03925"}'::jsonb,
    '{"city":"부산","district":"해운대구","street":"해운대해변로 264","zipcode":"48094"}'::jsonb,
    '{"city":"인천","district":"연수구","street":"송도과학로 32","zipcode":"21984"}'::jsonb,
    '{"city":"대전","district":"유성구","street":"대학로 99","zipcode":"34134"}'::jsonb,
    '{"city":"대구","district":"수성구","street":"달구벌대로 2503","zipcode":"42020"}'::jsonb,
    '{"city":"광주","district":"서구","street":"상무대로 1001","zipcode":"61945"}'::jsonb,
    '{"city":"수원","district":"영통구","street":"삼성로 129","zipcode":"16677"}'::jsonb,
    '{"city":"성남","district":"분당구","street":"판교역로 235","zipcode":"13494"}'::jsonb,
    '{"city":"제주","district":"제주시","street":"노형로 75","zipcode":"63099"}'::jsonb
  ];
  i INTEGER;
  order_id UUID;
  user_idx INTEGER;
  item_count INTEGER;
  j INTEGER;
  prod_id INTEGER;
  prod_price DECIMAL;
  prod_qty INTEGER;
  order_total DECIMAL;
BEGIN
  FOR i IN 1..200 LOOP
    order_id := gen_random_uuid();
    user_idx := (i % 50) + 1;
    order_total := 0;
    item_count := (random() * 4 + 1)::int;

    INSERT INTO orders (id, user_id, status, total_amount, shipping_address, created_at)
    VALUES (
      order_id,
      user_ids[user_idx],
      statuses[(random() * 8 + 1)::int],
      0,
      addresses[(random() * 9 + 1)::int],
      NOW() - (random() * 365 || ' days')::interval
    );

    FOR j IN 1..item_count LOOP
      prod_id := (random() * 999 + 1)::int;
      prod_price := (random() * 1990000 + 10000)::decimal(12,2);
      prod_qty := (random() * 3 + 1)::int;

      INSERT INTO order_items (order_id, product_id, product_name, quantity, unit_price, total_price)
      VALUES (
        order_id,
        'PROD-' || LPAD(prod_id::text, 4, '0'),
        CASE
          WHEN prod_id <= 100 THEN '전자제품 #' || prod_id
          WHEN prod_id <= 200 THEN '패션 아이템 #' || (prod_id - 100)
          WHEN prod_id <= 300 THEN '식품 #' || (prod_id - 200)
          WHEN prod_id <= 400 THEN '뷰티 제품 #' || (prod_id - 300)
          WHEN prod_id <= 500 THEN '가전 제품 #' || (prod_id - 400)
          WHEN prod_id <= 600 THEN '스포츠 용품 #' || (prod_id - 500)
          WHEN prod_id <= 700 THEN '도서 #' || (prod_id - 600)
          WHEN prod_id <= 800 THEN '반려동물 용품 #' || (prod_id - 700)
          WHEN prod_id <= 900 THEN '가구 #' || (prod_id - 800)
          ELSE '유아용품 #' || (prod_id - 900)
        END,
        prod_qty,
        prod_price,
        prod_price * prod_qty
      );
      order_total := order_total + (prod_price * prod_qty);
    END LOOP;

    UPDATE orders SET total_amount = order_total WHERE id = order_id;
  END LOOP;
END $$;

-- Payments (matching orders)
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'KRW',
  method VARCHAR(30) NOT NULL,
  status VARCHAR(30) DEFAULT 'completed',
  provider VARCHAR(50),
  transaction_id VARCHAR(100),
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO payments (order_id, amount, method, status, provider, transaction_id, created_at)
SELECT
  o.id,
  o.total_amount,
  (ARRAY['credit_card','kakao_pay','naver_pay','toss','bank_transfer'])[(random()*4+1)::int],
  CASE o.status
    WHEN 'cancelled' THEN 'refunded'
    WHEN 'returned' THEN 'refunded'
    WHEN 'pending' THEN 'pending'
    ELSE 'completed'
  END,
  (ARRAY['KG이니시스','NHN KCP','토스페이먼츠','카카오페이','네이버페이'])[(random()*4+1)::int],
  'TXN-' || encode(gen_random_uuid()::text::bytea, 'hex'),
  o.created_at
FROM orders o;

-- Inventory (1000 products)
CREATE TABLE IF NOT EXISTS inventory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id VARCHAR(50) UNIQUE NOT NULL,
  sku VARCHAR(50) NOT NULL,
  quantity_available INTEGER NOT NULL DEFAULT 0,
  quantity_reserved INTEGER NOT NULL DEFAULT 0,
  warehouse_id VARCHAR(20) DEFAULT 'WH-EAST-1',
  reorder_point INTEGER DEFAULT 10,
  last_restocked_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO inventory (product_id, sku, quantity_available, quantity_reserved, warehouse_id, reorder_point, last_restocked_at)
SELECT
  'PROD-' || LPAD(i::text, 4, '0'),
  'SKU-' || LPAD(i::text, 6, '0'),
  (random() * 500 + 5)::int,
  (random() * 20)::int,
  CASE WHEN random() > 0.5 THEN 'WH-EAST-1' ELSE 'WH-WEST-2' END,
  (random() * 20 + 5)::int,
  NOW() - (random() * 30 || ' days')::interval
FROM generate_series(1, 1000) AS i
ON CONFLICT (product_id) DO NOTHING;

-- Shipping table for fulfillment service
CREATE TABLE IF NOT EXISTS shipments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL,
  carrier VARCHAR(50),
  tracking_number VARCHAR(100),
  status VARCHAR(30) DEFAULT 'preparing',
  estimated_delivery DATE,
  shipped_at TIMESTAMP,
  delivered_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO shipments (order_id, carrier, tracking_number, status, estimated_delivery, shipped_at, delivered_at, created_at)
SELECT
  o.id,
  (ARRAY['CJ대한통운','한진택배','롯데택배','우체국택배','로젠택배'])[(random()*4+1)::int],
  'KR' || LPAD((random()*999999999)::bigint::text, 12, '0'),
  CASE o.status
    WHEN 'shipped' THEN 'in_transit'
    WHEN 'delivered' THEN 'delivered'
    WHEN 'processing' THEN 'preparing'
    ELSE 'preparing'
  END,
  (o.created_at + interval '3 days')::date,
  CASE WHEN o.status IN ('shipped','delivered') THEN o.created_at + interval '1 day' ELSE NULL END,
  CASE WHEN o.status = 'delivered' THEN o.created_at + interval '2 days' ELSE NULL END,
  o.created_at
FROM orders o
WHERE o.status IN ('processing','shipped','delivered');

-- Indexes
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_order_id ON payments(order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_product_id ON inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_shipments_order_id ON shipments(order_id);

SELECT 'Seed complete: ' || (SELECT count(*) FROM users) || ' users, ' ||
  (SELECT count(*) FROM orders) || ' orders, ' ||
  (SELECT count(*) FROM payments) || ' payments, ' ||
  (SELECT count(*) FROM inventory) || ' inventory items, ' ||
  (SELECT count(*) FROM shipments) || ' shipments';
