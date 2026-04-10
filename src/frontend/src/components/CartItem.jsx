import { useI18n } from '../context/I18nContext';

export default function CartItem({ item, onUpdateQuantity, onRemove }) {
  const { t } = useI18n();

  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };

  const renderStars = (rating) => {
    if (!rating) return null;
    const full = Math.floor(rating);
    const hasHalf = rating % 1 >= 0.5;
    return (
      <div className="flex items-center mt-2 text-brand-500">
        {[...Array(full)].map((_, i) => (
          <span key={i} className="material-symbols-outlined text-sm" style={{ fontVariationSettings: "'FILL' 1" }}>star</span>
        ))}
        {hasHalf && <span className="material-symbols-outlined text-sm">star_half</span>}
        {[...Array(5 - full - (hasHalf ? 1 : 0))].map((_, i) => (
          <span key={i} className="material-symbols-outlined text-sm text-outline-variant">star</span>
        ))}
        {item.reviewCount > 0 && (
          <span className="text-xs text-secondary ml-1">({item.reviewCount})</span>
        )}
      </div>
    );
  };

  return (
    <div className="py-8 flex flex-col md:flex-row gap-6 border-b border-outline-variant/10 last:border-0">
      <div className="w-full md:w-48 h-48 bg-surface-low rounded-lg overflow-hidden flex-shrink-0">
        <img
          src={item.imageUrl || item.image || `https://picsum.photos/seed/${item.productId}/400/400`}
          alt={item.name}
          className="w-full h-full object-cover"
        />
      </div>

      <div className="flex-grow flex flex-col justify-between">
        <div>
          <div className="flex justify-between items-start">
            <h2 className="text-xl font-bold text-on-surface font-[family-name:var(--font-headline)] leading-tight">{item.name}</h2>
            <span className="text-xl font-bold text-brand-900 font-[family-name:var(--font-headline)] ml-4 whitespace-nowrap">
              {formatPrice(item.price * item.quantity)}
            </span>
          </div>
          <p className="text-sm text-secondary mt-1">{t('cart.inStock')}</p>
          {item.price >= 50000 && (
            <p className="text-xs text-[#a99373] mt-2 font-medium">{t('cart.freeShipping')}</p>
          )}
          {renderStars(item.rating)}
        </div>

        <div className="mt-4 flex flex-wrap items-center gap-4 text-sm font-medium">
          <div className="flex items-center bg-surface-container rounded-md px-2 py-1 border border-outline-variant/30">
            <label className="text-xs text-secondary mr-2">{t('common.qty')}</label>
            <select
              value={item.quantity}
              onChange={(e) => onUpdateQuantity(item.productId, Number(e.target.value))}
              className="bg-transparent border-none focus:ring-0 text-sm py-0 pl-0 pr-6 cursor-pointer"
            >
              {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(n => (
                <option key={n} value={n}>{n}</option>
              ))}
            </select>
          </div>
          <div className="h-4 w-px bg-outline-variant/30 hidden md:block" />
          <button
            onClick={() => onRemove(item.productId)}
            className="text-brand-500 hover:underline decoration-2 underline-offset-4"
          >
            {t('cart.delete')}
          </button>
          <button className="text-brand-500 hover:underline decoration-2 underline-offset-4">
            {t('cart.saveLater')}
          </button>
          <button className="text-brand-500 hover:underline decoration-2 underline-offset-4">
            {t('cart.compare')}
          </button>
        </div>
      </div>
    </div>
  );
}
