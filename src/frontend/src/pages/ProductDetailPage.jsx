import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import ProductCard from '../components/ProductCard';
import ReviewCard from '../components/ReviewCard';
import { api, mapProduct } from '../api';

export default function ProductDetailPage() {
  const { id } = useParams();
  const { user } = useAuth();
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
        const [productRes, reviewsRes, similarRes] = await Promise.all([
          api(`/products/${id}`),
          api(`/reviews/product/${id}`).catch(() => ({ reviews: [] })),
          api(`/recommendations/similar/${id}`).catch(() => ({ products: [] })),
        ]);

        if (productRes) {
          setProduct(mapProduct(productRes));
        }

        const revs = (reviewsRes.reviews || []).map(r => ({
          id: r.id || r._id,
          userName: r.user_name || r.userName,
          rating: r.rating,
          content: r.body || r.content,
          createdAt: r.created_at || r.createdAt,
        }));
        setReviews(revs);

        const similar = (similarRes.products || similarRes.similar || []).map(mapProduct);
        setSimilarProducts(similar);
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

  const handleAddToCart = async () => {
    try {
      if (user?.id) {
        await api(`/carts/${user.id}`, {
          method: 'POST',
          body: JSON.stringify({
            product_id: product.id,
            name: product.name,
            quantity,
            price: product.price,
          }),
        });
      }
      for (let i = 0; i < quantity; i++) {
        incrementCart();
      }
      alert(`${product.name} ${quantity}개가 장바구니에 추가되었습니다.`);
    } catch (err) {
      console.error('장바구니 추가 API 오류:', err);
      alert('장바구니 추가에 실패했습니다.');
    }
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
            src={product.imageUrl || `https://picsum.photos/seed/${product.id}/800/800`}
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
        {reviews.length === 0 ? (
          <p className="text-slate-500 py-4">아직 리뷰가 없습니다.</p>
        ) : (
          <div className="space-y-4">
            {reviews.map((review) => (
              <ReviewCard key={review.id} review={review} />
            ))}
          </div>
        )}
      </section>

      {/* Similar Products */}
      {similarProducts.length > 0 && (
        <section>
          <h2 className="text-2xl font-bold text-slate-800 mb-6">비슷한 상품</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            {similarProducts.map((p) => (
              <ProductCard key={p.id} product={p} />
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
