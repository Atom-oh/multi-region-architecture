import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useCart } from '../context/CartContext';
import CartItem from '../components/CartItem';
import ProductCard from '../components/ProductCard';
import { api, mapProduct } from '../api';
import { useI18n } from '../context/I18nContext';

export default function CartPage() {
  const { t } = useI18n();
  const { user } = useAuth();
  const { updateCartCount } = useCart();
  const [cartItems, setCartItems] = useState([]);
  const [recommendations, setRecommendations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [promoOpen, setPromoOpen] = useState(false);

  useEffect(() => {
    const fetchCart = async () => {
      try {
        const data = await api(`/carts/${user.id}`);
        const items = (data.items || []).map(item => ({
          productId: item.product_id || item.productId,
          name: item.name,
          quantity: item.quantity,
          price: item.price,
          imageUrl: item.image_url || item.imageUrl,
          rating: item.rating || 0,
          reviewCount: item.review_count || item.reviewCount || 0,
        }));
        setCartItems(items);
        updateCartCount(items.reduce((sum, item) => sum + item.quantity, 0));
      } catch (error) {
        console.error('Failed to load cart:', error);
      } finally {
        setLoading(false);
      }
    };

    const fetchRecommendations = async () => {
      try {
        const data = await api(`/recommendations/${user.id}`);
        const products = (data.products || data || []).map(p => {
          if (p.product_id && !p.id && !p._id) p.id = p.product_id;
          return mapProduct(p);
        });
        setRecommendations(products.slice(0, 4));
      } catch {
        setRecommendations([]);
      }
    };

    fetchCart();
    fetchRecommendations();
  }, [user?.id]);

  const handleUpdateQuantity = async (productId, newQuantity) => {
    if (newQuantity < 1) return;
    setCartItems(prev =>
      prev.map(item =>
        item.productId === productId ? { ...item, quantity: newQuantity } : item
      )
    );
    const newTotal = cartItems.reduce((sum, item) =>
      item.productId === productId ? sum + newQuantity : sum + item.quantity, 0
    );
    updateCartCount(newTotal);
    try {
      await api(`/carts/${user.id}/items/${productId}`, { method: 'DELETE' });
      const item = cartItems.find(i => i.productId === productId);
      if (item) {
        await api(`/carts/${user.id}`, {
          method: 'POST',
          body: JSON.stringify({
            product_id: productId,
            name: item.name,
            quantity: newQuantity,
            price: item.price,
          }),
        });
      }
    } catch (error) {
      console.error('Failed to update quantity:', error);
    }
  };

  const handleRemove = async (productId) => {
    const newItems = cartItems.filter(item => item.productId !== productId);
    setCartItems(newItems);
    updateCartCount(newItems.reduce((sum, item) => sum + item.quantity, 0));
    try {
      await api(`/carts/${user.id}/items/${productId}`, { method: 'DELETE' });
    } catch (error) {
      console.error('Failed to remove item:', error);
    }
  };

  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };

  const subtotal = cartItems.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const itemCount = cartItems.reduce((sum, item) => sum + item.quantity, 0);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-secondary text-lg">{t('common.loading')}</p>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-4 md:px-8 py-8 md:py-12">
      {cartItems.length === 0 ? (
        <div className="text-center py-20">
          <span className="material-symbols-outlined text-outline-variant text-7xl mb-4 block">shopping_cart</span>
          <p className="text-secondary text-lg mb-6">{t('cart.empty')}</p>
          <Link
            to="/products"
            className="inline-block bg-brand-500 hover:bg-brand-700 text-white px-8 py-3 rounded-md font-bold transition-all shadow-md"
          >
            {t('cart.startShopping')}
          </Link>
        </div>
      ) : (
        <>
          <div className="flex flex-col lg:flex-row gap-8">
            {/* Cart Items */}
            <section className="lg:w-[70%]">
              <div className="bg-white p-6 md:p-8 rounded-xl shadow-sm">
                <h1 className="text-3xl font-extrabold text-brand-900 mb-2 font-[family-name:var(--font-headline)]">{t('cart.title')}</h1>
                <p className="text-secondary text-sm border-b border-outline-variant/20 pb-4">
                  {t('cart.subtitle')}
                </p>

                <div className="divide-y divide-outline-variant/10">
                  {cartItems.map((item) => (
                    <CartItem
                      key={item.productId}
                      item={item}
                      onUpdateQuantity={handleUpdateQuantity}
                      onRemove={handleRemove}
                    />
                  ))}
                </div>

                {/* Mobile Subtotal */}
                <div className="lg:hidden mt-6 text-right border-t border-outline-variant/20 pt-6">
                  <p className="text-lg">
                    {t('cart.subtotal', { count: itemCount })}{' '}
                    <span className="font-extrabold text-brand-900 font-[family-name:var(--font-headline)] text-xl">
                      {formatPrice(subtotal)}
                    </span>
                  </p>
                </div>
              </div>
            </section>

            {/* Checkout Sidebar */}
            <aside className="lg:w-[30%] space-y-6">
              <div className="bg-white p-6 rounded-xl shadow-lg border-t-4 border-brand-500 sticky top-20">
                <div className="mb-4">
                  <p className="text-lg font-medium text-on-surface">
                    {t('cart.subtotal', { count: itemCount })}
                  </p>
                  <p className="text-3xl font-extrabold text-brand-900 font-[family-name:var(--font-headline)]">
                    {formatPrice(subtotal)}
                  </p>
                </div>

                <div className="flex items-start gap-3 mb-6 bg-surface-low p-3 rounded-md">
                  <input
                    type="checkbox"
                    id="gift"
                    className="mt-1 rounded border-outline focus:ring-brand-500 text-brand-500"
                  />
                  <label htmlFor="gift" className="text-sm text-secondary leading-tight">
                    {t('cart.gift')}
                  </label>
                </div>

                <Link
                  to="/checkout"
                  className="block w-full py-4 bg-brand-500 hover:bg-brand-700 text-white font-bold rounded-md shadow-md shadow-brand-500/20 text-center transition-all uppercase tracking-wider text-sm font-[family-name:var(--font-headline)] mb-4"
                >
                  {t('cart.checkout')}
                </Link>

                {/* Promotions Applied */}
                <div className="pt-4 border-t border-outline-variant/20">
                  <button
                    onClick={() => setPromoOpen(!promoOpen)}
                    className="w-full flex items-center justify-between text-sm font-medium text-secondary hover:text-brand-900 transition-colors group"
                  >
                    <span>{t('cart.promotions')}</span>
                    <span className={`material-symbols-outlined text-sm transition-transform ${promoOpen ? 'rotate-180' : ''}`}>
                      expand_more
                    </span>
                  </button>
                  {promoOpen && (
                    <div className="mt-3 p-3 bg-surface-low rounded-md text-sm text-secondary">
                      No promotions currently applied.
                    </div>
                  )}
                </div>
              </div>

              {/* Rewards Card */}
              <div className="bg-brand-900 p-6 rounded-xl text-white">
                <h3 className="font-bold text-lg mb-2 font-[family-name:var(--font-headline)]">{t('cart.rewards')}</h3>
                <p className="text-sm text-white/70 mb-4">
                  {t('cart.rewardsDesc')}
                </p>
                <a href="#" className="text-brand-300 text-sm font-bold hover:underline">{t('cart.learnMore')}</a>
              </div>
            </aside>
          </div>

          {/* Recommendations Carousel */}
          {recommendations.length > 0 && (
            <section className="mt-16">
              <h2 className="text-2xl font-extrabold text-brand-900 mb-8 font-[family-name:var(--font-headline)]">
                {t('cart.alsoRecommended')}
              </h2>
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
                {recommendations.map((product) => (
                  <ProductCard key={product.id} product={product} />
                ))}
              </div>
            </section>
          )}
        </>
      )}
    </div>
  );
}
