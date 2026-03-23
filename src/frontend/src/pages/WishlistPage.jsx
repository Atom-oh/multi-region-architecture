import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useCart } from '../context/CartContext';
import { api } from '../api';

export default function WishlistPage() {
  const { user } = useAuth();
  const { incrementCart } = useCart();
  const [wishlist, setWishlist] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchWishlist = async () => {
      try {
        const data = await api(`/wishlists/${user.id}`);
        const items = (data.items || data || []).map(item => ({
          id: item.product_id || item.id,
          name: item.name,
          price: item.price,
          rating: item.rating || 0,
          reviewCount: item.review_count || item.reviewCount || 0,
          imageUrl: item.images?.[0] || item.image_url || item.imageUrl,
        }));
        setWishlist(items);
      } catch (error) {
        console.error('데이터를 불러올 수 없습니다:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchWishlist();
  }, [user?.id]);

  const formatPrice = (price) => {
    return `₩${price.toLocaleString('ko-KR')}`;
  };

  const renderStars = (rating) => {
    const fullStars = Math.floor(rating);
    const emptyStars = 5 - fullStars;
    return (
      <span className="text-yellow-400">
        {'★'.repeat(fullStars)}
        <span className="text-slate-300">{'☆'.repeat(emptyStars)}</span>
      </span>
    );
  };

  const handleRemove = async (productId) => {
    try {
      if (user?.id) {
        await api(`/wishlists/${user.id}/items/${productId}`, { method: 'DELETE' });
      }
    } catch (err) {
      console.error('위시리스트 삭제 API 오류:', err);
    }
    setWishlist(prev => prev.filter(item => item.id !== productId));
  };

  const handleAddToCart = async (product) => {
    try {
      if (user?.id) {
        await api(`/carts/${user.id}`, {
          method: 'POST',
          body: JSON.stringify({
            product_id: product.id,
            name: product.name,
            quantity: 1,
            price: product.price,
          }),
        });
      }
      incrementCart();
      alert(`${product.name}이(가) 장바구니에 추가되었습니다.`);
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

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold text-slate-800 mb-8">위시리스트</h1>

      {wishlist.length === 0 ? (
        <div className="text-center py-16">
          <svg className="w-24 h-24 text-slate-300 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
          </svg>
          <p className="text-slate-500 text-lg mb-4">위시리스트가 비어있습니다.</p>
          <Link
            to="/products"
            className="inline-block bg-blue-500 text-white px-6 py-3 rounded-lg font-medium hover:bg-blue-600 transition-colors"
          >
            상품 둘러보기
          </Link>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {wishlist.map((product) => (
            <div key={product.id} className="bg-white rounded-lg shadow-sm overflow-hidden group">
              <div className="relative">
                <Link to={`/products/${product.id}`}>
                  <div className="aspect-square bg-slate-100 overflow-hidden">
                    <img
                      src={product.imageUrl || `https://picsum.photos/seed/${product.id}/400/400`}
                      alt={product.name}
                      className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                    />
                  </div>
                </Link>
                <button
                  onClick={() => handleRemove(product.id)}
                  className="absolute top-2 right-2 w-8 h-8 bg-white rounded-full shadow flex items-center justify-center hover:bg-red-50 transition-colors"
                >
                  <svg className="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z" />
                  </svg>
                </button>
              </div>

              <div className="p-4">
                <Link to={`/products/${product.id}`}>
                  <h3 className="font-medium text-slate-800 truncate hover:text-blue-500 transition-colors">
                    {product.name}
                  </h3>
                </Link>
                <div className="flex items-center gap-1 my-2">
                  {renderStars(product.rating)}
                  <span className="text-sm text-slate-500">({product.reviewCount})</span>
                </div>
                <p className="text-lg font-bold text-blue-600 mb-3">{formatPrice(product.price)}</p>
                <button
                  onClick={() => handleAddToCart(product)}
                  className="w-full bg-blue-500 text-white py-2 rounded-lg text-sm font-medium hover:bg-blue-600 transition-colors"
                >
                  장바구니 담기
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
