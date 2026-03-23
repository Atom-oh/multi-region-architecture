import { Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';

export default function ProductCard({ product }) {
  const { incrementCart } = useCart();

  const formatPrice = (price) => {
    return `₩${price.toLocaleString('ko-KR')}`;
  };

  const renderStars = (rating) => {
    const fullStars = Math.floor(rating);
    const hasHalf = rating % 1 >= 0.5;
    const emptyStars = 5 - fullStars - (hasHalf ? 1 : 0);
    return (
      <span className="text-yellow-400">
        {'★'.repeat(fullStars)}
        {hasHalf && '★'}
        <span className="text-slate-300">{'☆'.repeat(emptyStars)}</span>
      </span>
    );
  };

  const handleAddToCart = (e) => {
    e.preventDefault();
    e.stopPropagation();
    incrementCart();
  };

  return (
    <Link
      to={`/products/${product.id}`}
      className="bg-white rounded-lg shadow-md overflow-hidden hover:shadow-xl transition-shadow duration-300 group"
    >
      <div className="aspect-square bg-slate-100 overflow-hidden">
        <img
          src={product.imageUrl || `https://picsum.photos/seed/${product.id}/400/400`}
          alt={product.name}
          className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
        />
      </div>
      <div className="p-4">
        <h3 className="font-medium text-slate-800 truncate mb-1">{product.name}</h3>
        <div className="flex items-center gap-1 mb-2">
          {renderStars(product.rating || 4.5)}
          <span className="text-sm text-slate-500">({product.reviewCount || 0})</span>
        </div>
        <div className="flex items-center justify-between">
          <p className="text-lg font-bold text-blue-600">{formatPrice(product.price)}</p>
          <button
            onClick={handleAddToCart}
            className="bg-blue-500 text-white px-3 py-1 rounded-lg text-sm hover:bg-blue-600 transition-colors"
          >
            담기
          </button>
        </div>
      </div>
    </Link>
  );
}
