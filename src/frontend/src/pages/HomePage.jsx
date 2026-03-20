import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import ProductCard from '../components/ProductCard';

const MOCK_PRODUCTS = [
  { id: 'PRD-001', name: '삼성 갤럭시 S24 Ultra', price: 1890000, rating: 4.8, reviewCount: 1234, category: 'electronics' },
  { id: 'PRD-002', name: 'LG 그램 17인치 노트북', price: 2190000, rating: 4.7, reviewCount: 856, category: 'electronics' },
  { id: 'PRD-003', name: '나이키 에어맥스 97', price: 219000, rating: 4.6, reviewCount: 2341, category: 'fashion' },
  { id: 'PRD-004', name: '다이슨 V15 무선청소기', price: 1290000, rating: 4.9, reviewCount: 567, category: 'home' },
  { id: 'PRD-005', name: '애플 맥북 프로 14', price: 2890000, rating: 4.9, reviewCount: 1892, category: 'electronics' },
  { id: 'PRD-006', name: '소니 WH-1000XM5 헤드폰', price: 449000, rating: 4.8, reviewCount: 3421, category: 'electronics' },
  { id: 'PRD-007', name: '무지 린넨 셔츠', price: 59000, rating: 4.5, reviewCount: 892, category: 'fashion' },
  { id: 'PRD-008', name: '필립스 에어프라이어 XXL', price: 329000, rating: 4.7, reviewCount: 1567, category: 'home' },
];

const TRENDING_PRODUCTS = [
  { id: 'PRD-009', name: '아이패드 프로 12.9', price: 1729000, rating: 4.9, reviewCount: 2134, category: 'electronics' },
  { id: 'PRD-010', name: '구찌 마몬트 백', price: 2890000, rating: 4.8, reviewCount: 456, category: 'fashion' },
  { id: 'PRD-011', name: '발뮤다 토스터', price: 329000, rating: 4.6, reviewCount: 789, category: 'home' },
  { id: 'PRD-012', name: '아디다스 울트라부스트', price: 239000, rating: 4.7, reviewCount: 1823, category: 'fashion' },
];

const CATEGORIES = [
  { id: 'electronics', name: '전자제품', icon: '📱', color: 'bg-blue-100' },
  { id: 'fashion', name: '패션', icon: '👗', color: 'bg-pink-100' },
  { id: 'home', name: '홈/리빙', icon: '🏠', color: 'bg-green-100' },
  { id: 'beauty', name: '뷰티', icon: '💄', color: 'bg-purple-100' },
  { id: 'sports', name: '스포츠', icon: '⚽', color: 'bg-orange-100' },
  { id: 'food', name: '식품', icon: '🍎', color: 'bg-red-100' },
];

export default function HomePage() {
  const [featuredProducts, setFeaturedProducts] = useState([]);
  const [trendingProducts, setTrendingProducts] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchData = async () => {
      try {
        // In production, these would be real API calls
        // const products = await api('/products');
        // const trending = await api('/recommendations/trending');

        // Using mock data for demo
        await new Promise(resolve => setTimeout(resolve, 500));
        setFeaturedProducts(MOCK_PRODUCTS);
        setTrendingProducts(TRENDING_PRODUCTS);
      } catch (error) {
        console.error('데이터를 불러올 수 없습니다:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, []);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-slate-500 text-lg">로딩 중...</p>
      </div>
    );
  }

  return (
    <div>
      {/* Hero Banner */}
      <section className="bg-gradient-to-r from-slate-800 to-slate-900 text-white">
        <div className="max-w-7xl mx-auto px-4 py-16 md:py-24">
          <div className="max-w-2xl">
            <h1 className="text-4xl md:text-5xl font-bold mb-4">
              글로벌 쇼핑의<br />새로운 기준
            </h1>
            <p className="text-slate-300 text-lg mb-8">
              전 세계 어디서나 빠르고 안정적인 쇼핑 경험.<br />
              Multi-Region Mall에서 특별한 상품을 만나보세요.
            </p>
            <Link
              to="/products"
              className="inline-block bg-blue-500 text-white px-8 py-3 rounded-lg font-medium hover:bg-blue-600 transition-colors"
            >
              쇼핑 시작하기
            </Link>
          </div>
        </div>
      </section>

      {/* Category Navigation */}
      <section className="bg-slate-50 py-8">
        <div className="max-w-7xl mx-auto px-4">
          <div className="grid grid-cols-3 md:grid-cols-6 gap-4">
            {CATEGORIES.map((category) => (
              <Link
                key={category.id}
                to={`/products?category=${category.id}`}
                className={`${category.color} rounded-xl p-4 text-center hover:shadow-md transition-shadow`}
              >
                <span className="text-3xl mb-2 block">{category.icon}</span>
                <span className="text-sm font-medium text-slate-700">{category.name}</span>
              </Link>
            ))}
          </div>
        </div>
      </section>

      {/* Featured Products */}
      <section className="py-12">
        <div className="max-w-7xl mx-auto px-4">
          <div className="flex items-center justify-between mb-8">
            <h2 className="text-2xl font-bold text-slate-800">추천 상품</h2>
            <Link to="/products" className="text-blue-500 hover:text-blue-600 font-medium">
              전체보기 →
            </Link>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            {featuredProducts.map((product) => (
              <ProductCard key={product.id} product={product} />
            ))}
          </div>
        </div>
      </section>

      {/* Promotion Banner */}
      <section className="bg-blue-500 py-12">
        <div className="max-w-7xl mx-auto px-4 text-center text-white">
          <h2 className="text-3xl font-bold mb-4">신규 가입 혜택</h2>
          <p className="text-blue-100 text-lg mb-6">
            지금 가입하면 첫 구매 20% 할인 쿠폰을 드립니다!
          </p>
          <Link
            to="/register"
            className="inline-block bg-white text-blue-500 px-8 py-3 rounded-lg font-medium hover:bg-blue-50 transition-colors"
          >
            회원가입
          </Link>
        </div>
      </section>

      {/* Trending Products */}
      <section className="py-12 bg-slate-50">
        <div className="max-w-7xl mx-auto px-4">
          <div className="flex items-center justify-between mb-8">
            <h2 className="text-2xl font-bold text-slate-800">지금 인기있는 상품</h2>
            <Link to="/products" className="text-blue-500 hover:text-blue-600 font-medium">
              전체보기 →
            </Link>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            {trendingProducts.map((product) => (
              <ProductCard key={product.id} product={product} />
            ))}
          </div>
        </div>
      </section>

      {/* Trust Badges */}
      <section className="py-12">
        <div className="max-w-7xl mx-auto px-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8 text-center">
            <div className="p-6">
              <div className="w-16 h-16 bg-blue-100 rounded-full flex items-center justify-center mx-auto mb-4">
                <svg className="w-8 h-8 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
              </div>
              <h3 className="text-lg font-bold text-slate-800 mb-2">100% 정품 보장</h3>
              <p className="text-slate-500">모든 상품은 정품만 취급합니다</p>
            </div>
            <div className="p-6">
              <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
                <svg className="w-8 h-8 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <h3 className="text-lg font-bold text-slate-800 mb-2">빠른 배송</h3>
              <p className="text-slate-500">주문 후 1-2일 내 배송</p>
            </div>
            <div className="p-6">
              <div className="w-16 h-16 bg-purple-100 rounded-full flex items-center justify-center mx-auto mb-4">
                <svg className="w-8 h-8 text-purple-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                </svg>
              </div>
              <h3 className="text-lg font-bold text-slate-800 mb-2">안전한 결제</h3>
              <p className="text-slate-500">안전한 결제 시스템 제공</p>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
