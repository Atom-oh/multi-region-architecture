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

  // Convert date strings to Date objects and strip upload-only fields
  return rawProducts.map(({ image_sources, ...p }) => ({
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

// ── 10,000 Reviews ─────────────────────────────────────────────────────────
function generateReviews(products) {
  // Category-specific review bodies by sentiment
  const categoryReviews = {
    electronics: {
      positive: [
        '화면이 정말 선명하고 배터리도 하루 종일 넉넉해요.',
        '성능이 미쳤어요. 앱 전환도 끊김 없이 매끄럽습니다.',
        '카메라 품질이 놀라워요. 야간 촬영도 훌륭합니다.',
        '전작 대비 확실히 업그레이드된 느낌이에요.',
        '가볍고 얇은데 성능은 데스크톱급이에요. 최고!',
        '발열도 적고 팬 소음도 거의 없어서 조용히 작업할 수 있어요.',
        '충전 속도가 빨라서 30분이면 80% 충전돼요.',
        '음질이 깔끔하고 노이즈캔슬링 성능이 탁월합니다.',
      ],
      neutral: [
        '무난하게 쓸 만한 수준이에요. 크게 불만은 없습니다.',
        '가격 대비 괜찮은데 특별히 뛰어나진 않아요.',
        '디자인은 예쁜데 무게감이 좀 있어요.',
        '기본 기능은 충실한데 부가 기능은 아쉬워요.',
      ],
      negative: [
        '배터리가 반나절도 안 가요. 심각한 수준입니다.',
        '발열이 너무 심해서 게임은 힘들어요.',
        '화면에 잔상이 생기네요. AS 맡길 예정입니다.',
        '스피커 음질이 이 가격대에서는 너무 아쉽습니다.',
      ],
    },
    fashion: {
      positive: [
        '원단이 부드럽고 핏이 정말 예뻐요! 강추합니다.',
        '사진이랑 실물이 똑같아요. 색감 너무 좋습니다.',
        '봄에 입기 딱 좋은 두께에요. 코디하기 쉬워요.',
        '세탁해도 줄지 않고 형태가 잘 유지돼요.',
        '재질이 고급스럽고 마감 처리가 꼼꼼해요.',
        '남자친구한테 선물했는데 반응이 너무 좋았어요.',
        '가격 대비 퀄리티가 정말 좋아요. 재구매 확정!',
        '오버핏이라 편하게 입기 좋아요. 사이즈 참고하세요.',
      ],
      neutral: [
        '나쁘지 않은데 가격이 좀 있는 편이에요.',
        '핏은 괜찮은데 원단이 좀 얇아요.',
        '색상이 사진과 약간 다르지만 나쁘지 않아요.',
        '무난하게 입을 수 있어요. 특별한 건 없습니다.',
      ],
      negative: [
        '한 번 빨았는데 늘어나고 보풀이 생겼어요.',
        '사이즈가 많이 작아요. 한 사이즈 업 추천합니다.',
        '실밥이 풀려있었어요. 검수가 부실한 것 같아요.',
        '색상이 사진이랑 완전 달라서 실망했습니다.',
      ],
    },
    food: {
      positive: [
        '맛이 진짜 좋아요! 자꾸 손이 갑니다.',
        '아이들이 너무 좋아해요. 간식으로 딱이에요.',
        '유통기한도 넉넉하고 포장이 꼼꼼해요.',
        '밥반찬으로 최고예요. 매번 재구매합니다.',
        '선물용으로 포장이 고급스러워요.',
        '건강하게 먹을 수 있어서 좋아요. 첨가물 없이 깔끔합니다.',
        '냉동이라 걱정했는데 해동 후 맛이 정말 좋아요.',
        '가성비 최고! 마트보다 훨씬 싸고 맛있어요.',
      ],
      neutral: [
        '맛은 괜찮은데 양이 생각보다 적어요.',
        '나쁘지 않은데 기대만큼은 아니에요.',
        '간이 좀 약한 편이에요. 개인 차이가 있을 듯.',
        '보통 맛이에요. 재구매는 고민 중입니다.',
      ],
      negative: [
        '유통기한이 얼마 안 남은 게 와서 실망이에요.',
        '포장이 뜯어져서 왔어요. 배송 중 파손된 것 같습니다.',
        '짜기만 하고 맛이 없어요. 기대 이하입니다.',
        '사진이랑 양이 너무 달라요. 미니어처 수준...',
      ],
    },
    beauty: {
      positive: [
        '피부에 잘 맞고 보습력이 뛰어나요!',
        '향이 은은하고 발림성이 좋아요. 피부 결이 좋아졌어요.',
        '민감한 피부인데 자극 없이 순하게 사용하고 있어요.',
        '한 달 사용했는데 확실히 피부 톤이 밝아졌어요.',
        '가볍게 발리고 끈적임 없어서 여름에도 좋아요.',
        '용량 대비 가성비가 좋고 오래 써요.',
        '메이크업 베이스로 쓰기 좋아요. 밀착력 최고!',
        '성분이 깨끗해서 안심하고 사용합니다.',
      ],
      neutral: [
        '보습력은 괜찮은데 향이 좀 강한 편이에요.',
        '효과가 바로 느껴지진 않아요. 좀 더 써봐야 할 것 같아요.',
        '무난하게 쓸 만해요. 특별한 효과는 모르겠어요.',
        '용량이 생각보다 적어요. 금방 쓸 것 같아요.',
      ],
      negative: [
        '바르자마자 빨갛게 올라왔어요. 민감 피부 주의하세요.',
        '끈적이고 흡수가 안 돼요. 무거운 느낌이에요.',
        '효과를 전혀 모르겠어요. 비싼 돈 내고 후회합니다.',
        '펌프가 고장났어요. 두 번이나 교환했습니다.',
      ],
    },
    appliances: {
      positive: [
        '소음이 정말 적어요! 밤에 돌려도 전혀 시끄럽지 않아요.',
        '에너지 효율 1등급이라 전기세 걱정 없어요.',
        '설치 기사분이 친절하셨고, 제품도 만족스러워요.',
        '생각보다 콤팩트한데 성능은 대형 못지않아요.',
        '매일 사용하는데 1년째 고장 없이 잘 쓰고 있어요.',
        '세척이 간편해서 관리하기 편해요.',
        '자동 모드가 편리하고 세밀하게 조절됩니다.',
        '인테리어에 딱 어울리는 디자인이에요.',
      ],
      neutral: [
        '성능은 괜찮은데 크기가 좀 커요.',
        '가격 대비 무난한 편이에요.',
        '기본 기능은 좋은데 부가 기능이 좀 아쉬워요.',
        '소음이 생각보다 조금 있어요. 그래도 쓸만합니다.',
      ],
      negative: [
        '한 달 만에 고장났어요. 내구성이 걱정됩니다.',
        '소음이 너무 심해서 밤에 사용이 불가능해요.',
        '전기세가 많이 나오네요. 에너지 효율이 낮은 것 같아요.',
        '냄새가 빠지지 않아요. 처음 사용 시 환기 필수입니다.',
      ],
    },
    sports: {
      positive: [
        '착용감이 정말 좋아요! 운동할 때 불편함이 전혀 없어요.',
        '쿠셔닝이 뛰어나서 무릎 부담이 확 줄었어요.',
        '방수 기능이 확실해요. 비 올 때도 걱정 없습니다.',
        '가볍고 통기성이 좋아서 여름 운동에 최적이에요.',
        '그립감이 좋고 내구성도 뛰어나요.',
        '초보자한테도 추천합니다. 사용하기 편해요.',
        '프로 선수도 사용한다길래 구매했는데 확실히 다르네요.',
        '디자인도 예쁘고 기능성도 뛰어나서 만족합니다.',
      ],
      neutral: [
        '무난하게 쓸 수 있어요. 가격 대비 보통입니다.',
        '사이즈가 약간 크게 나와요. 반 사이즈 아래로 추천.',
        '디자인은 좋은데 내구성이 좀 걱정돼요.',
        '기능은 괜찮은데 가격이 좀 비싼 편이에요.',
      ],
      negative: [
        '일주일 만에 솔기가 뜯어졌어요.',
        '사이즈가 전혀 안 맞아요. 교환도 번거로워요.',
        '방수라더니 비 오면 물이 스며들어요.',
        '쿠셔닝이 금방 없어져요. 내구성이 아쉽습니다.',
      ],
    },
    books: {
      positive: [
        '한 번 읽기 시작하면 멈출 수 없어요. 몰입감 최고!',
        '인생 책입니다. 여러 번 읽어도 새로운 깨달음이 있어요.',
        '번역이 자연스럽고 읽기 편해요.',
        '깊이 있는 내용인데 쉽게 풀어서 좋았어요.',
        '선물로 드렸더니 정말 좋아하셨어요.',
        '생각이 많아지는 책이에요. 강력 추천합니다.',
        '두고두고 다시 읽고 싶은 책이에요.',
        '일상에 바로 적용할 수 있는 실용적인 내용입니다.',
      ],
      neutral: [
        '나쁘지 않은데 기대만큼은 아니었어요.',
        '전반부는 좋았는데 후반부가 아쉬워요.',
        '가볍게 읽기 좋은 책이에요.',
        '내용은 좋은데 번역이 조금 어색한 부분이 있어요.',
      ],
      negative: [
        '기대가 컸는데 내용이 너무 얕아서 실망했어요.',
        '반복되는 내용이 많아서 지루했습니다.',
        '인쇄 상태가 좋지 않아요. 글씨가 흐릿해요.',
        '책이 구겨진 채로 왔어요. 포장이 너무 부실합니다.',
      ],
    },
    pets: {
      positive: [
        '우리 강아지가 정말 좋아해요! 밥그릇 앞에서 기다립니다.',
        '기호성도 좋고 변 상태가 눈에 띄게 좋아졌어요.',
        '무항생제 원료라 안심하고 급여합니다.',
        '고양이가 잘 먹어요. 알레르기 반응도 없습니다.',
        '털에 윤기가 나기 시작했어요. 확실히 좋은 사료입니다.',
        '소형견한테 사이즈가 딱 맞아요. 잘 물어요.',
        '첨가물 없이 원재료가 좋아서 믿고 급여해요.',
        '소분 포장이라 신선하게 줄 수 있어서 좋아요.',
      ],
      neutral: [
        '먹긴 먹는데 열광하지는 않아요.',
        '가격이 좀 있지만 성분 생각하면 그럭저럭.',
        '알갱이 크기가 약간 큰 편이에요.',
        '괜찮은데 전에 먹이던 것과 큰 차이를 모르겠어요.',
      ],
      negative: [
        '우리 고양이는 입도 안 대요. 기호성 최악입니다.',
        '먹고 나서 설사를 해요. 맞지 않는 것 같습니다.',
        '포장이 찢어져서 왔어요. 사료가 다 쏟아졌습니다.',
        '유통기한 임박 상품을 보냈네요. 양심이 없네요.',
      ],
    },
    furniture: {
      positive: [
        '조립이 쉽고 완성도가 높아요! 인테리어 효과 최고.',
        '원목 질감이 사진보다 실물이 훨씬 좋아요.',
        '튼튼하고 안정감 있어요. 가구는 역시 이 브랜드!',
        '수납공간이 넉넉해서 정리정돈이 편해졌어요.',
        '배송 기사분이 원하는 위치에 설치까지 해주셨어요.',
        '2년째 쓰고 있는데 변형 없이 튼튼해요.',
        '미니멀한 디자인이 모던 인테리어에 딱 맞아요.',
        '가격 대비 마감이 훌륭해요. 강추합니다.',
      ],
      neutral: [
        '무난한 디자인이에요. 가격도 적당합니다.',
        '조립이 좀 복잡한데 완성하면 괜찮아요.',
        '색상이 모니터랑 약간 달라요. 그래도 예뻐요.',
        '사이즈를 잘 확인하세요. 생각보다 커요.',
      ],
      negative: [
        '조립 설명서가 불친절해요. 부품도 하나 빠져있었어요.',
        '한 달 만에 서랍이 뒤틀렸어요. 품질이 실망스럽습니다.',
        '배송 중 모서리가 찍혀서 왔어요.',
        '냄새가 심해요. 일주일 넘게 환기해도 안 빠져요.',
      ],
    },
    baby: {
      positive: [
        '아기가 정말 좋아해요! 안전하고 귀엽습니다.',
        'KC 인증이라 안심하고 사용합니다.',
        '유기농 소재라 민감한 아기 피부에도 안전해요.',
        '디자인이 예쁘고 실용적이에요. 선물용으로도 좋아요.',
        '세탁해도 형태 변형이 없어요. 내구성 좋습니다.',
        '가볍고 휴대하기 편해서 외출할 때 꼭 챙겨요.',
        '아이가 잡기 쉬운 사이즈에요. 월령에 딱 맞아요.',
        '독일제라 그런지 마감이 정말 꼼꼼해요.',
      ],
      neutral: [
        '괜찮은데 가격이 좀 비싼 편이에요.',
        '아이가 크게 관심을 보이지는 않아요.',
        '나쁘지 않은데 다른 브랜드와 큰 차이를 모르겠어요.',
        '사이즈가 좀 작아요. 나이 기준보다 체형으로 고르세요.',
      ],
      negative: [
        '플라스틱 냄새가 심해요. BPA-free 맞나요?',
        '아이가 사용하기엔 모서리가 날카로워요.',
        '일주일 만에 부서졌어요. 내구성 제로입니다.',
        '사진이랑 실물 차이가 너무 심해요.',
      ],
    },
  };

  // Review titles by rating range
  const titles5 = [
    '완벽해요! 강력 추천합니다', '인생템 발견!', '대만족입니다 ★★★★★',
    '두 번 세 번 재구매 의사 있어요', '이 가격에 이 품질? 최고!',
    '기대 이상이에요', '선물로 줘도 좋을 것 같아요', '역대급 만족',
    '고민하지 마시고 그냥 사세요', '진작 살 걸 그랬어요',
  ];
  const titles4 = [
    '만족스러운 구매', '가성비 좋아요', '추천합니다!',
    '전반적으로 만족해요', '괜찮은 제품이에요', '무난하게 좋습니다',
    '재구매 의사 있어요', '기대만큼 좋았어요',
  ];
  const titles3 = [
    '보통이에요', '그저 그래요', '나쁘지 않아요',
    '가격 생각하면 이 정도?', '평범한 제품입니다', '기대에는 못 미쳐요',
  ];
  const titles2 = [
    '좀 아쉬워요', '기대 이하입니다', '다시는 안 살 것 같아요',
    '돈이 아깝네요', '개선이 필요해요', '실망입니다',
  ];
  const titles1 = [
    '최악이에요', '환불하고 싶어요', '절대 비추합니다',
    '사지 마세요', '돈 낭비입니다', '이건 진짜 아니에요',
  ];
  const titlesByRating = { 5: titles5, 4: titles4, 3: titles3, 2: titles2, 1: titles1 };

  // User names pool
  const userNames = [
    '김민지', '이서준', '박지우', '최수현', '정하윤', '강도현', '조은서', '윤시우',
    '장하은', '임준서', '한소율', '오지호', '서윤아', '신민재', '권나은', '황태민',
    '송예린', '류지안', '문채원', '배승우', '백서영', '홍준혁', '남다은', '유하린',
    '전우진', '양시연', '심지훈', '노아영', '하재민', '구소희', '안현우', '차유나',
    '봉지석', '피세아', '추미래', '진서현', '탁선영', '옥승리', '석다운', '판유리',
    '고은채', '길태양', '맹별솔', '도하늘', '마루한', '소은별', '감나래', '곽빛나',
    '반하루', '설단비',
  ];

  // Weighted rating distribution: ~10% 1★, ~10% 2★, ~15% 3★, ~30% 4★, ~35% 5★
  function weightedRating() {
    const r = Math.random() * 100;
    if (r < 10) return 1;
    if (r < 20) return 2;
    if (r < 35) return 3;
    if (r < 65) return 4;
    return 5;
  }

  function pickReviewBody(categorySlug, rating) {
    const cat = categoryReviews[categorySlug] || categoryReviews.electronics;
    let pool;
    if (rating >= 4) pool = cat.positive;
    else if (rating === 3) pool = cat.neutral;
    else pool = cat.negative;
    return pool[Math.floor(Math.random() * pool.length)];
  }

  const reviews = [];
  for (let i = 0; i < 10000; i++) {
    const product = products[i % products.length];
    const categorySlug = product.category?.slug || 'electronics';
    const userIdx = i % 50;
    const user_id = `a0000001-0000-0000-0000-${String(userIdx + 1).padStart(12, '0')}`;
    const rating = weightedRating();
    const titles = titlesByRating[rating];
    const now = new Date(Date.now() - Math.random() * 365 * 86400000);
    reviews.push({
      id: `rev-${String(i + 1).padStart(5, '0')}`,
      user_id,
      user_name: userNames[userIdx],
      product_id: product.productId,
      rating,
      title: titles[Math.floor(Math.random() * titles.length)],
      body: pickReviewBody(categorySlug, rating),
      images: i % 7 === 0 ? [`https://mall.atomai.click/images/reviews/${i + 1}/photo.webp`] : [],
      helpful_count: rating >= 4 ? Math.floor(Math.random() * 80) : Math.floor(Math.random() * 30),
      verified_purchase: Math.random() > 0.15,
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
