// ============================================================================
// Multi-Region Shopping Mall - DocumentDB (MongoDB) Seed Data
// Services: product-catalog, user-profile, wishlist, review, notification
// ============================================================================

const { MongoClient } = require('mongodb');
const fs = require('fs');
const path = require('path');

const MONGO_URI = process.env.DOCUMENTDB_URI || 'mongodb://docdb_admin:<YOUR_PASSWORD>@localhost:27017/mall?tls=true&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false&authMechanism=SCRAM-SHA-1';
const DB_NAME = 'mall';

// ── 10 Categories ──────────────────────────────────────────────────────────
const categories = [
  { id: 'CAT-01', name: '전자제품', slug: 'electronics', icon: 'laptop', sortOrder: 1 },
  { id: 'CAT-02', name: '패션', slug: 'fashion', icon: 'shirt', sortOrder: 2 },
  { id: 'CAT-03', name: '식품', slug: 'food', icon: 'utensils', sortOrder: 3 },
  { id: 'CAT-04', name: '뷰티', slug: 'beauty', icon: 'sparkles', sortOrder: 4 },
  { id: 'CAT-05', name: '가전', slug: 'appliances', icon: 'tv', sortOrder: 5 },
  { id: 'CAT-06', name: '스포츠', slug: 'sports', icon: 'dumbbell', sortOrder: 6 },
  { id: 'CAT-07', name: '도서', slug: 'books', icon: 'book', sortOrder: 7 },
  { id: 'CAT-08', name: '반려동물', slug: 'pets', icon: 'paw-print', sortOrder: 8 },
  { id: 'CAT-09', name: '가구', slug: 'furniture', icon: 'sofa', sortOrder: 9 },
  { id: 'CAT-10', name: '유아용품', slug: 'baby', icon: 'baby', sortOrder: 10 },
];

// ── 1000 Products (loaded from generated JSON) ────────────────────────────
function generateProducts() {
  const jsonPath = path.join(__dirname, 'products-1000.json');
  const rawProducts = JSON.parse(fs.readFileSync(jsonPath, 'utf-8'));

  // Convert date strings to Date objects for DocumentDB
  return rawProducts.map(p => ({
    ...p,
    createdAt: new Date(p.createdAt),
    updatedAt: new Date(p.updatedAt),
  }));
}

// ── (Legacy product data removed — now loaded from products-1000.json) ────
// ── 50 User Profiles ───────────────────────────────────────────────────────
function generateUserProfiles() {
  const names = [
    '김민준','이소연','박지훈','최유나','정도연','강시우','윤하은','신지원','한서준','오민지',
    '서준혁','권수빈','임태양','송은지','백현우','장나연','황동현','안채원','유상민','노지영',
    '문해진','고연수','홍건우','배수영','조민서','남우진','양하영','류재현','하지민','우승호',
    '차예린','공태희','민성우','변아름','손재민','임수진','표강현','지희선','탁영재','구다혜',
    '마현수','피은비','도원호','가수연','사준우','타지혜','나찬호','라미래','다용준','바선화',
  ];
  return names.map((name, i) => {
    const userId = `a0000001-0000-0000-0000-${String(i + 1).padStart(12, '0')}`;
    const tier = ['bronze','silver','silver','gold','gold','gold','platinum','platinum','diamond','vip'][i % 10];
    return {
      userId,
      name,
      tier,
      points: Math.floor(Math.random() * 100000),
      preferences: {
        language: 'ko',
        currency: 'KRW',
        categories: [categories[i % 10].slug, categories[(i + 3) % 10].slug],
        notificationEnabled: true,
        emailMarketing: i % 3 !== 0,
      },
      addresses: [{
        label: '집',
        city: ['서울','부산','인천','대전','대구','광주','수원','성남','제주','울산'][i % 10],
        isDefault: true,
      }],
      lastLoginAt: new Date(Date.now() - Math.random() * 30 * 86400000),
      createdAt: new Date(Date.now() - Math.random() * 365 * 86400000),
    };
  });
}

// ── 30 Wishlists ───────────────────────────────────────────────────────────
function generateWishlists(products) {
  const wishlists = [];
  for (let i = 0; i < 50; i++) {
    const user_id = `a0000001-0000-0000-0000-${String((i % 50) + 1).padStart(12, '0')}`;
    const itemCount = Math.floor(Math.random() * 8 + 2);
    const items = [];
    const used = new Set();
    for (let j = 0; j < itemCount; j++) {
      let idx;
      do { idx = Math.floor(Math.random() * products.length); } while (used.has(idx));
      used.add(idx);
      items.push({
        product_id: products[idx].productId,
        name: products[idx].name,
        price: products[idx].price,
        added_at: new Date(Date.now() - Math.random() * 90 * 86400000),
      });
    }
    const created = new Date(Date.now() - Math.random() * 180 * 86400000);
    wishlists.push({
      user_id,
      items,
      created_at: created,
      updated_at: created,
    });
  }
  return wishlists;
}

// ── 300 Reviews ────────────────────────────────────────────────────────────
function generateReviews(products) {
  const comments = [
    '정말 좋은 제품이에요! 강력 추천합니다.',
    '가성비가 뛰어나네요. 만족합니다.',
    '배송도 빠르고 포장도 꼼꼼했어요.',
    '품질이 기대 이상이에요. 재구매 의사 있습니다.',
    '디자인이 예쁘고 실용적이에요.',
    '사용해보니 생각보다 괜찮네요.',
    '선물용으로 샀는데 반응이 좋았어요.',
    '가격 대비 훌륭합니다.',
    '오래 사용해도 튼튼하네요.',
    '색상이 사진이랑 좀 달라요.',
    '기대했던 것보다는 보통이에요.',
    '사이즈가 딱 맞아요. 좋습니다.',
    '매장에서 보고 온라인으로 구매했어요.',
    '세일 때 사서 더 좋았어요!',
    '두 번째 구매인데 여전히 만족합니다.',
  ];

  const reviews = [];
  for (let i = 0; i < 2000; i++) {
    const product = products[i % products.length];
    const user_id = `a0000001-0000-0000-0000-${String((i % 50) + 1).padStart(12, '0')}`;
    const rating = Math.floor(Math.random() * 3 + 3); // 3-5
    const now = new Date(Date.now() - Math.random() * 180 * 86400000);
    reviews.push({
      id: `rev-${String(i + 1).padStart(4, '0')}`,
      user_id,
      user_name: '',
      product_id: product.productId,
      rating,
      title: rating >= 4 ? '만족스러운 구매' : '보통이에요',
      body: comments[i % comments.length],
      images: i % 5 === 0 ? [`https://cdn.mall.example.com/reviews/${i + 1}/photo.webp`] : [],
      helpful_count: Math.floor(Math.random() * 50),
      verified_purchase: i % 3 !== 2,
      created_at: now,
      updated_at: now,
    });
  }
  return reviews;
}

// ── 50 Notifications ───────────────────────────────────────────────────────
function generateNotifications() {
  const types = [
    { type: 'order_shipped', title: '주문하신 상품이 발송되었습니다', channel: 'push' },
    { type: 'order_delivered', title: '배송이 완료되었습니다', channel: 'push' },
    { type: 'promotion', title: '오늘만 특가! 최대 50% 할인', channel: 'email' },
    { type: 'point_earned', title: '포인트가 적립되었습니다', channel: 'push' },
    { type: 'price_drop', title: '위시리스트 상품 가격이 내렸어요!', channel: 'push' },
    { type: 'review_request', title: '구매하신 상품의 리뷰를 작성해주세요', channel: 'email' },
    { type: 'coupon', title: '새로운 쿠폰이 발급되었습니다', channel: 'sms' },
    { type: 'restock', title: '품절 상품이 다시 입고되었습니다', channel: 'push' },
  ];

  const notifications = [];
  for (let i = 0; i < 50; i++) {
    const userId = `a0000001-0000-0000-0000-${String((i % 50) + 1).padStart(12, '0')}`;
    const tmpl = types[i % types.length];
    notifications.push({
      userId,
      type: tmpl.type,
      title: tmpl.title,
      body: `${tmpl.title} - 자세한 내용을 확인하세요.`,
      channel: tmpl.channel,
      read: i % 3 === 0,
      metadata: { orderId: i % 4 < 2 ? `ORD-${String(i + 1000).padStart(6, '0')}` : null },
      sentAt: new Date(Date.now() - Math.random() * 30 * 86400000),
    });
  }
  return notifications;
}

// ── 500 User Activities (for recommendation engine) ─────────────────────
function generateUserActivities(products) {
  const actions = ['view', 'click', 'add_to_cart', 'purchase'];
  const actionWeights = [50, 25, 15, 10]; // % distribution
  const activities = [];

  for (let i = 0; i < 3000; i++) {
    const user_id = `a0000001-0000-0000-0000-${String((i % 50) + 1).padStart(12, '0')}`;
    const product = products[Math.floor(Math.random() * products.length)];

    // Weighted random action selection
    const rand = Math.random() * 100;
    let action;
    if (rand < actionWeights[0]) action = actions[0];
    else if (rand < actionWeights[0] + actionWeights[1]) action = actions[1];
    else if (rand < actionWeights[0] + actionWeights[1] + actionWeights[2]) action = actions[2];
    else action = actions[3];

    activities.push({
      user_id,
      product_id: product.productId,
      action,
      category: product.category.slug,
      timestamp: new Date(Date.now() - Math.random() * 30 * 86400000),
      metadata: {
        source: ['home', 'search', 'category', 'recommendation'][Math.floor(Math.random() * 4)],
      },
    });
  }
  return activities;
}

// ── Main ───────────────────────────────────────────────────────────────────
async function main() {
  const client = new MongoClient(MONGO_URI, {
    tls: true,
    tlsCAFile: process.env.TLS_CA_FILE || '/tmp/global-bundle.pem',
    retryWrites: false,
  });

  try {
    await client.connect();
    console.log('Connected to DocumentDB');
    const db = client.db(DB_NAME);

    // Categories
    await db.collection('categories').deleteMany({});
    await db.collection('categories').insertMany(categories);
    console.log(`Inserted ${categories.length} categories`);

    // Products
    const products = generateProducts();
    await db.collection('products').deleteMany({});
    await db.collection('products').insertMany(products);
    console.log(`Inserted ${products.length} products`);

    // Create indexes
    await db.collection('products').createIndex({ productId: 1 }, { unique: true });
    await db.collection('products').createIndex({ 'category.slug': 1 });
    await db.collection('products').createIndex({ brand: 1 });
    await db.collection('products').createIndex({ price: 1 });
    await db.collection('products').createIndex({ rating: -1 });

    // User Profiles
    const profiles = generateUserProfiles();
    await db.collection('user_profiles').deleteMany({});
    await db.collection('user_profiles').insertMany(profiles);
    console.log(`Inserted ${profiles.length} user profiles`);
    await db.collection('user_profiles').createIndex({ userId: 1 }, { unique: true });

    // Wishlists
    const wishlists = generateWishlists(products);
    await db.collection('wishlists').deleteMany({});
    await db.collection('wishlists').insertMany(wishlists);
    console.log(`Inserted ${wishlists.length} wishlists`);
    await db.collection('wishlists').createIndex({ user_id: 1 });

    // Reviews (snake_case fields to match review_repo.py)
    const reviews = generateReviews(products);
    await db.collection('reviews').deleteMany({});
    await db.collection('reviews').insertMany(reviews);
    console.log(`Inserted ${reviews.length} reviews`);
    await db.collection('reviews').createIndex({ product_id: 1 });
    await db.collection('reviews').createIndex({ user_id: 1 });
    await db.collection('reviews').createIndex({ id: 1 }, { unique: true });
    await db.collection('reviews').createIndex({ rating: -1 });

    // Notifications
    const notifications = generateNotifications();
    await db.collection('notifications').deleteMany({});
    await db.collection('notifications').insertMany(notifications);
    console.log(`Inserted ${notifications.length} notifications`);
    await db.collection('notifications').createIndex({ userId: 1, sentAt: -1 });

    // User Activities (for recommendation engine)
    const activities = generateUserActivities(products);
    await db.collection('user_activities').deleteMany({});
    await db.collection('user_activities').insertMany(activities);
    console.log(`Inserted ${activities.length} user activities`);
    await db.collection('user_activities').createIndex({ user_id: 1, timestamp: -1 });
    await db.collection('user_activities').createIndex({ product_id: 1 });
    await db.collection('user_activities').createIndex({ action: 1 });

    console.log('\nSeed complete!');
    console.log(`  ${categories.length} categories`);
    console.log(`  ${products.length} products`);
    console.log(`  ${profiles.length} user profiles`);
    console.log(`  ${wishlists.length} wishlists (scaled for 1000 products)`);
    console.log(`  ${reviews.length} reviews (scaled for 1000 products)`);
    console.log(`  ${notifications.length} notifications`);
    console.log(`  ${activities.length} user activities (scaled for 1000 products)`);
  } finally {
    await client.close();
  }
}

main().catch(console.error);
