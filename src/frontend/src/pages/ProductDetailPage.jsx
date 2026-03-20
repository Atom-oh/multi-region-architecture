import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import ProductCard from '../components/ProductCard';
import ReviewCard from '../components/ReviewCard';

const MOCK_PRODUCTS = {
  'PRD-001': { id: 'PRD-001', name: '삼성 갤럭시 S24 Ultra', price: 1890000, rating: 4.8, reviewCount: 1234, category: 'electronics', description: '최신 AI 기능을 탑재한 프리미엄 스마트폰. 200MP 카메라, S펜 내장, 티타늄 프레임으로 제작되었습니다.' },
  'PRD-002': { id: 'PRD-002', name: 'LG 그램 17인치 노트북', price: 2190000, rating: 4.7, reviewCount: 856, category: 'electronics', description: '초경량 1.35kg의 17인치 대화면 노트북. 인텔 13세대 프로세서, 16GB RAM, 512GB SSD 탑재.' },
  'PRD-003': { id: 'PRD-003', name: '나이키 에어맥스 97', price: 219000, rating: 4.6, reviewCount: 2341, category: 'fashion', description: '클래식한 디자인의 에어맥스 97. 풀 렝스 에어 유닛으로 편안한 착화감을 제공합니다.' },
  'PRD-004': { id: 'PRD-004', name: '다이슨 V15 무선청소기', price: 1290000, rating: 4.9, reviewCount: 567, category: 'home', description: '레이저 먼지 감지 기술로 보이지 않는 먼지까지 깨끗하게. 60분 연속 사용 가능.' },
  'PRD-005': { id: 'PRD-005', name: '애플 맥북 프로 14', price: 2890000, rating: 4.9, reviewCount: 1892, category: 'electronics', description: 'M3 Pro 칩 탑재, 18시간 배터리, Liquid Retina XDR 디스플레이.' },
};

const MOCK_REVIEWS = [
  { id: 'REV-001', userName: '이지현', rating: 5, content: '정말 좋은 제품이에요! 배송도 빠르고 품질도 최고입니다.', createdAt: '2024-03-15' },
  { id: 'REV-002', userName: '박민수', rating: 4, content: '전체적으로 만족스럽습니다. 가격 대비 성능이 좋아요.', createdAt: '2024-03-10' },
  { id: 'REV-003', userName: '김서연', rating: 5, content: '기대 이상이었어요. 디자인도 예쁘고 사용하기 편해요.', createdAt: '2024-03-05' },
];

const SIMILAR_PRODUCTS = [
  { id: 'PRD-006', name: '소니 WH-1000XM5 헤드폰', price: 449000, rating: 4.8, reviewCount: 3421, category: 'electronics' },
  { id: 'PRD-009', name: '아이패드 프로 12.9', price: 1729000, rating: 4.9, reviewCount: 2134, category: 'electronics' },
  { id: 'PRD-016', name: '로지텍 MX Master 3S', price: 149000, rating: 4.8, reviewCount: 2345, category: 'electronics' },
  { id: 'PRD-013', name: '삼성 QLED 75인치 TV', price: 3490000, rating: 4.8, reviewCount: 432, category: 'electronics' },
];

export default function ProductDetailPage() {
  const { id } = useParams();
  const { incrementCart } = useCart();
  const [product, setProduct] = useState(null);
  const [reviews, setReviews] = useState([]);
  const [similarProducts, setSimilarProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [quantity, setQuantity] = useState(1);

  useEffect(() => {
    const fetchProduct = async () => {
      setLoading(true);
      try {
        // In production: const data = await api(`/products/${id}`);
        await new Promise(resolve => setTimeout(resolve, 300));

        const productData = MOCK_PRODUCTS[id] || {
          id,
          name: '상품명',
          price: 100000,
          rating: 4.5,
          reviewCount: 100,
          category: 'electronics',
          description: '상품 설명입니다.',
        };

        setProduct(productData);
        setReviews(MOCK_REVIEWS);
        setSimilarProducts(SIMILAR_PRODUCTS);
      } catch (error) {
        console.error('데이터를 불러올 수 없습니다:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchProduct();
  }, [id]);

  const formatPrice = (price) => {
    return `₩${price.toLocaleString('ko-KR')}`;
  };

  const renderStars = (rating) => {
    const fullStars = Math.floor(rating);
    const hasHalf = rating % 1 >= 0.5;
    const emptyStars = 5 - fullStars - (hasHalf ? 1 : 0);
    return (
      <span className="text-yellow-400 text-xl">
        {'★'.repeat(fullStars)}
        {hasHalf && '★'}
        <span className="text-slate-300">{'☆'.repeat(emptyStars)}</span>
      </span>
    );
  };

  const handleAddToCart = () => {
    for (let i = 0; i < quantity; i++) {
      incrementCart();
    }
    alert(`${product.name} ${quantity}개가 장바구니에 추가되었습니다.`);
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-slate-500 text-lg">로딩 중...</p>
      </div>
    );
  }

  if (!product) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-slate-500 text-lg">상품을 찾을 수 없습니다.</p>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      {/* Breadcrumb */}
      <nav className="text-sm text-slate-500 mb-6">
        <Link to="/" className="hover:text-blue-500">홈</Link>
        <span className="mx-2">/</span>
        <Link to="/products" className="hover:text-blue-500">상품</Link>
        <span className="mx-2">/</span>
        <span className="text-slate-800">{product.name}</span>
      </nav>

      {/* Product Detail */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 mb-16">
        <div className="aspect-square bg-slate-100 rounded-2xl overflow-hidden">
          <img
            src={`https://picsum.photos/seed/${product.id}/800/800`}
            alt={product.name}
            className="w-full h-full object-cover"
          />
        </div>

        <div>
          <h1 className="text-3xl font-bold text-slate-800 mb-4">{product.name}</h1>

          <div className="flex items-center gap-2 mb-4">
            {renderStars(product.rating)}
            <span className="text-slate-500">({product.reviewCount} 리뷰)</span>
          </div>

          <p className="text-4xl font-bold text-blue-600 mb-6">
            {formatPrice(product.price)}
          </p>

          <p className="text-slate-600 mb-8 leading-relaxed">
            {product.description}
          </p>

          <div className="flex items-center gap-4 mb-6">
            <span className="text-slate-700 font-medium">수량:</span>
            <div className="flex items-center">
              <button
                onClick={() => setQuantity(Math.max(1, quantity - 1))}
                className="w-10 h-10 rounded-l-lg bg-slate-100 hover:bg-slate-200 flex items-center justify-center transition-colors"
              >
                -
              </button>
              <span className="w-12 h-10 bg-slate-50 flex items-center justify-center font-medium">
                {quantity}
              </span>
              <button
                onClick={() => setQuantity(quantity + 1)}
                className="w-10 h-10 rounded-r-lg bg-slate-100 hover:bg-slate-200 flex items-center justify-center transition-colors"
              >
                +
              </button>
            </div>
          </div>

          <div className="flex gap-4">
            <button
              onClick={handleAddToCart}
              className="flex-1 bg-blue-500 text-white py-4 rounded-lg font-medium hover:bg-blue-600 transition-colors"
            >
              장바구니 담기
            </button>
            <Link
              to="/checkout"
              className="flex-1 bg-slate-800 text-white py-4 rounded-lg font-medium hover:bg-slate-900 transition-colors text-center"
            >
              바로 구매
            </Link>
          </div>

          <div className="mt-8 p-4 bg-slate-50 rounded-lg">
            <h3 className="font-medium text-slate-800 mb-2">배송 안내</h3>
            <ul className="text-sm text-slate-600 space-y-1">
              <li>- 무료 배송 (50,000원 이상 구매 시)</li>
              <li>- 오늘 주문 시 내일 도착</li>
              <li>- 30일 이내 무료 반품</li>
            </ul>
          </div>
        </div>
      </div>

      {/* Reviews Section */}
      <section className="mb-16">
        <h2 className="text-2xl font-bold text-slate-800 mb-6">상품 리뷰</h2>
        <div className="space-y-4">
          {reviews.map((review) => (
            <ReviewCard key={review.id} review={review} />
          ))}
        </div>
      </section>

      {/* Similar Products */}
      <section>
        <h2 className="text-2xl font-bold text-slate-800 mb-6">비슷한 상품</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {similarProducts.map((p) => (
            <ProductCard key={p.id} product={p} />
          ))}
        </div>
      </section>
    </div>
  );
}
