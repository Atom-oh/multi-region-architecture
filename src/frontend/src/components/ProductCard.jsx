import { Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import { api } from '../api';
import { useI18n } from '../context/I18nContext';

export default function ProductCard({ product }) {
  const { t } = useI18n();
  const { incrementCart } = useCart();
  const { user } = useAuth();

  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };

  const renderStars = (rating) => {
    const full = Math.floor(rating);
    const hasHalf = rating % 1 >= 0.5;
    return (
      <div className="flex items-center text-brand-500">
        {[...Array(full)].map((_, i) => (
          <span key={i} className="material-symbols-outlined material-filled text-[14px]">star</span>
        ))}
        {hasHalf && <span className="material-symbols-outlined text-[14px]">star_half</span>}
        {[...Array(5 - full - (hasHalf ? 1 : 0))].map((_, i) => (
          <span key={i} className="material-symbols-outlined text-[14px] text-outline-variant">star</span>
        ))}
      </div>
    );
  };

  const handleAddToCart = async (e) => {
    e.preventDefault();
    e.stopPropagation();
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
    } catch (err) {
      console.error('Failed to add to cart:', err);
    }
  };

  return (
    <Link
      to={`/products/${product.id}`}
      className="bg-white rounded-xl overflow-hidden hover:shadow-xl transition-all border border-transparent hover:border-outline-variant/10 group block"
    >
      <div className="aspect-square bg-surface-container overflow-hidden">
        <img
          src={product.imageUrl || `https://picsum.photos/seed/${product.id}/400/400`}
          alt={product.name}
          className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
        />
      </div>
      <div className="p-4">
        <h3 className="font-bold text-on-surface group-hover:text-brand-500 transition-colors truncate mb-1 font-[family-name:var(--font-headline)]">
          {product.name}
        </h3>
        <div className="flex items-center gap-1 mb-2">
          {renderStars(product.rating || 4.5)}
          <span className="text-xs text-secondary ml-1">({product.reviewCount || 0})</span>
        </div>
        <div className="flex items-center justify-between mt-3">
          <p className="text-lg font-bold text-brand-900 font-[family-name:var(--font-headline)]">{formatPrice(product.price)}</p>
          <button
            onClick={handleAddToCart}
            className="bg-surface-high hover:bg-brand-500 hover:text-white text-on-surface px-3 py-1.5 rounded-md text-xs font-bold transition-colors uppercase tracking-tight"
          >
            {t('products.addToCart')}
          </button>
        </div>
      </div>
    </Link>
  );
}
