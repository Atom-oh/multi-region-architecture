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

// Legacy product data removed — now loaded from products-1000.json
// Previously had 150 hardcoded products (15 per category × 10 categories)
const _LEGACY_REMOVED = {
  'CAT-01': [
    'CAT-02': [
      { name: '나이키 에어맥스 DN', price: 199000, brand: 'Nike' },
      { name: '아디다스 울트라부스트 24', price: 229000, brand: 'Adidas' },
      { name: '유니클로 히트텍 울트라웜', price: 39900, brand: 'UNIQLO' },
      { name: '자라 오버사이즈 블레이저', price: 159000, brand: 'ZARA' },
      { name: '뉴발란스 993 러닝화', price: 259000, brand: 'New Balance' },
      { name: '노스페이스 눕시 패딩', price: 369000, brand: 'The North Face' },
      { name: '구찌 마몽 숄더백', price: 2890000, brand: 'Gucci' },
      { name: '리바이스 501 오리지널 진', price: 129000, brand: "Levi's" },
      { name: '폴로 랄프로렌 케이블 니트', price: 289000, brand: 'Polo Ralph Lauren' },
      { name: '컨버스 척테일러 올스타', price: 69000, brand: 'Converse' },
      { name: '무신사 스탠다드 맨투맨', price: 29900, brand: '무신사 스탠다드' },
      { name: 'MLB 뉴욕양키스 볼캡', price: 39900, brand: 'MLB' },
      { name: '디스커버리 롱패딩', price: 459000, brand: 'Discovery' },
      { name: '코오롱 안타티카 패딩', price: 699000, brand: 'KOLON SPORT' },
      { name: '빈폴 체크 셔츠', price: 119000, brand: 'BEANPOLE' },
    ],
    'CAT-03': [
      { name: '곰표 밀가루 2.5kg', price: 5900, brand: '대한제분' },
      { name: '농심 신라면 멀티팩', price: 4980, brand: '농심' },
      { name: '오뚜기 진라면 매운맛', price: 4500, brand: '오뚜기' },
      { name: '비비고 왕교자 1kg', price: 12900, brand: 'CJ비비고' },
      { name: '풀무원 두부 찌개용', price: 2500, brand: '풀무원' },
      { name: '서울우유 1L', price: 2800, brand: '서울우유' },
      { name: '하겐다즈 바닐라 파인트', price: 9900, brand: 'Häagen-Dazs' },
      { name: '스타벅스 원두 하우스블렌드', price: 15900, brand: 'Starbucks' },
      { name: '곰곰 무항생제 달걀 30구', price: 8900, brand: '곰곰' },
      { name: '제주삼다수 2L 6본', price: 5400, brand: '삼다수' },
      { name: '종가집 포기김치 3kg', price: 22900, brand: '종가집' },
      { name: '참이슬 후레쉬 360ml 20본', price: 28900, brand: '하이트진로' },
      { name: '카스 프레시 500ml 12캔', price: 16900, brand: 'OB맥주' },
      { name: '동원 참치캔 150g 5입', price: 9900, brand: '동원' },
      { name: '오리온 초코파이 12입', price: 4900, brand: '오리온' },
    ],
    'CAT-04': [
      { name: '설화수 자음생크림', price: 179000, brand: '설화수' },
      { name: '에스티로더 어드밴스 나이트 리페어', price: 135000, brand: 'Estée Lauder' },
      { name: '라네즈 워터 슬리핑 마스크', price: 32000, brand: '라네즈' },
      { name: '이니스프리 그린티 세럼', price: 25000, brand: '이니스프리' },
      { name: '헤라 블랙 쿠션', price: 55000, brand: 'HERA' },
      { name: 'SK-II 피테라 에센스', price: 189000, brand: 'SK-II' },
      { name: '닥터자르트 시카페어 크림', price: 48000, brand: 'Dr.Jart+' },
      { name: '아모레 비오템 옴므 세트', price: 65000, brand: 'Biotherm' },
      { name: '클리오 킬커버 파운데이션', price: 28000, brand: 'CLIO' },
      { name: 'VT 리들샷 100 에센스', price: 23000, brand: 'VT' },
      { name: '마녀공장 퓨어 클렌징 오일', price: 18000, brand: '마녀공장' },
      { name: '토니모리 달팽이 크림', price: 22000, brand: 'TONYMOLY' },
      { name: '미샤 타임레볼루션 앰플', price: 35000, brand: 'MISSHA' },
      { name: '코스알엑스 스네일 에센스', price: 19000, brand: 'COSRX' },
      { name: '에뛰드 플레이컬러 아이즈', price: 24000, brand: 'ETUDE' },
    ],
    'CAT-05': [
      { name: 'LG 스탠바이미 Go', price: 1090000, brand: 'LG전자' },
      { name: '삼성 비스포크 냉장고 4도어', price: 2890000, brand: '삼성전자' },
      { name: 'LG 트롬 워시타워', price: 2490000, brand: 'LG전자' },
      { name: '삼성 비스포크 에어컨', price: 1990000, brand: '삼성전자' },
      { name: 'LG 퓨리케어 공기청정기', price: 699000, brand: 'LG전자' },
      { name: '다이슨 V15 디텍트', price: 1190000, brand: 'Dyson' },
      { name: '쿠쿠 IH 전기밥솥', price: 399000, brand: '쿠쿠' },
      { name: '필립스 에어프라이어 XXL', price: 329000, brand: 'Philips' },
      { name: '삼성 비스포크 식기세척기', price: 1290000, brand: '삼성전자' },
      { name: 'LG 코드제로 A9S', price: 899000, brand: 'LG전자' },
      { name: '위닉스 제습기 16L', price: 389000, brand: '위닉스' },
      { name: '브레빌 바리스타 익스프레스', price: 799000, brand: 'Breville' },
      { name: '발뮤다 더 토스터', price: 299000, brand: 'BALMUDA' },
      { name: '일렉트로룩스 로봇청소기', price: 599000, brand: 'Electrolux' },
      { name: 'LG 디오스 오브제컬렉션 전자레인지', price: 399000, brand: 'LG전자' },
    ],
    'CAT-06': [
      { name: '나이키 드라이핏 반팔 티', price: 45000, brand: 'Nike' },
      { name: '요넥스 배드민턴 라켓 아스트록스', price: 289000, brand: 'YONEX' },
      { name: '윌슨 프로스태프 테니스 라켓', price: 359000, brand: 'Wilson' },
      { name: '가민 포러너 265', price: 529000, brand: 'Garmin' },
      { name: '블랙야크 등산화 트레킹', price: 189000, brand: 'BLACKYAK' },
      { name: '데카트론 요가매트 8mm', price: 29900, brand: 'Decathlon' },
      { name: '나이키 줌 페가수스 41', price: 159000, brand: 'Nike' },
      { name: '아디다스 프레데터 축구화', price: 199000, brand: 'Adidas' },
      { name: '미즈노 웨이브라이더 28', price: 179000, brand: 'MIZUNO' },
      { name: '언더아머 퍼포먼스 폴로', price: 79000, brand: 'Under Armour' },
      { name: '살로몬 스피드크로스 6', price: 189000, brand: 'Salomon' },
      { name: '핑 G430 드라이버', price: 699000, brand: 'PING' },
      { name: '타이틀리스트 프로V1 골프공', price: 69000, brand: 'Titleist' },
      { name: '코베아 캠핑 텐트 4인용', price: 459000, brand: 'KOVEA' },
      { name: '스노우피크 티타늄 머그', price: 59000, brand: 'Snow Peak' },
    ],
    'CAT-07': [
      { name: '원씽: 복잡한 세상을 이기는 단순함의 힘', price: 14400, brand: '비즈니스북스' },
      { name: '아토믹 해빗', price: 16200, brand: '비즈니스북스' },
      { name: '역행자', price: 17100, brand: '웅진지식하우스' },
      { name: '불편한 편의점 3', price: 14400, brand: '나무옆의자' },
      { name: '트렌드 코리아 2026', price: 19800, brand: '미래의창' },
      { name: '세이노의 가르침', price: 6480, brand: '데이원' },
      { name: '데일 카네기 인간관계론', price: 16200, brand: '현대지성' },
      { name: '이것이 자바다 (개정판)', price: 36000, brand: '한빛미디어' },
      { name: '클린 코드', price: 33000, brand: '인사이트' },
      { name: '파친코 (양장본)', price: 18900, brand: '문학사상' },
      { name: '해리포터 시리즈 전집', price: 108000, brand: '문학수첩' },
      { name: 'Do it! 점프 투 파이썬', price: 18800, brand: '이지스퍼블리싱' },
      { name: '코스모스 (칼 세이건)', price: 22500, brand: '사이언스북스' },
      { name: '지구끝의 온실', price: 14400, brand: '자이언트북스' },
      { name: '나미야 잡화점의 기적', price: 14400, brand: '현대문학' },
    ],
    'CAT-08': [
      { name: '로얄캐닌 인도어 고양이사료 4kg', price: 49000, brand: 'Royal Canin' },
      { name: '오리젠 오리지널 독 6kg', price: 89000, brand: 'ORIJEN' },
      { name: '퓨리나 프로플랜 연어 7kg', price: 55000, brand: 'Purina' },
      { name: '캣타워 대형 나무 놀이터', price: 89000, brand: '펫트리' },
      { name: '강아지 자동급식기 5L', price: 59000, brand: '페코' },
      { name: '고양이 화장실 후드형', price: 45000, brand: '캣아이디어' },
      { name: '반려동물 이동장 항공형', price: 35000, brand: '리치엘' },
      { name: '강아지 하네스 세트', price: 25000, brand: '줄리어스K9' },
      { name: '고양이 스크래처 골판지', price: 12000, brand: '네이처펫' },
      { name: '반려동물 자동 물분수', price: 39000, brand: '카타잇' },
      { name: '강아지 치석제거 덴탈껌', price: 15000, brand: '그리니스' },
      { name: '고양이 츄르 참치 20개입', price: 12000, brand: '이나바' },
      { name: '반려동물 GPS 트래커', price: 99000, brand: '핏빗펫' },
      { name: '강아지 방석 메모리폼 L', price: 49000, brand: '보듬' },
      { name: '고양이 장난감 깃털 낚시대', price: 8000, brand: '캣폴' },
    ],
    'CAT-09': [
      { name: '이케아 칼락스 선반유닛', price: 79900, brand: 'IKEA' },
      { name: '한샘 시스템 옷장 3.2m', price: 2990000, brand: '한샘' },
      { name: '일룸 쿠시노 소파 3인', price: 1890000, brand: '일룸' },
      { name: '시디즈 T80 사무용 의자', price: 599000, brand: 'SIDIZ' },
      { name: '에이스침대 하이브리드 퀸', price: 3490000, brand: '에이스침대' },
      { name: '리바트 원목 식탁세트 6인', price: 1290000, brand: '리바트' },
      { name: '이케아 말름 서랍장 6칸', price: 229000, brand: 'IKEA' },
      { name: '데스커 모션데스크 1400', price: 799000, brand: 'DESKER' },
      { name: '한샘 수납 책장 5단', price: 349000, brand: '한샘' },
      { name: '이케아 포엥 암체어', price: 199000, brand: 'IKEA' },
      { name: '일룸 키즈 성장 책상', price: 890000, brand: '일룸' },
      { name: '쁘띠메종 LED 거울', price: 159000, brand: '쁘띠메종' },
      { name: '니토리 접이식 매트리스', price: 199000, brand: 'NITORI' },
      { name: '코지 패브릭 1인 소파', price: 299000, brand: 'COZY' },
      { name: '무인양품 스택식 선반', price: 129000, brand: 'MUJI' },
    ],
    'CAT-10': [
      { name: '싸이벡스 프리암 유모차', price: 1590000, brand: 'Cybex' },
      { name: '스토케 트립트랩 하이체어', price: 449000, brand: 'Stokke' },
      { name: '하기스 맥스드라이 기저귀 L', price: 35900, brand: '하기스' },
      { name: '보령 앱솔루트 분유 3단계', price: 29900, brand: '보령' },
      { name: '닥터브라운 젖병 세트', price: 39000, brand: "Dr. Brown's" },
      { name: '레고 듀플로 대형 놀이상자', price: 69900, brand: 'LEGO' },
      { name: '피셔프라이스 아기 체육관', price: 55000, brand: 'Fisher-Price' },
      { name: '에르고베이비 옴니 360', price: 289000, brand: 'Ergobaby' },
      { name: '베베숲 물티슈 80매 10팩', price: 15900, brand: '베베숲' },
      { name: '맥시코시 카시트 투비스', price: 490000, brand: 'Maxi-Cosi' },
      { name: '아가방 신생아 내의 세트', price: 32000, brand: '아가방' },
      { name: '브이텍 학습 테이블', price: 59000, brand: 'VTech' },
      { name: '콤비 유모차 스고칼', price: 890000, brand: 'Combi' },
      { name: '포디언 아기침대 범퍼세트', price: 129000, brand: '포디언' },
      { name: '누크 이유식 조리기', price: 89000, brand: 'NUK' },
    ],
  };

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
