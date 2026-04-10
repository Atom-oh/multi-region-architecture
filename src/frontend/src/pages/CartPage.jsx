import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useCart } from '../context/CartContext';
import CartItem from '../components/CartItem';
import { api } from '../api';
import { useI18n } from '../context/I18nContext';

export default function CartPage() {
  const { t } = useI18n();
  const { user } = useAuth();
  const { updateCartCount } = useCart();
  const [cartItems, setCartItems] = useState([]);
  const [loading, setLoading] = useState(true);

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
        }));
        setCartItems(items);
        updateCartCount(items.reduce((sum, item) => sum + item.quantity, 0));
      } catch (error) {
        console.error('Failed to load cart:', error);
      } finally {
        setLoading(false);
      }
    };
    fetchCart();
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
        <div className="flex flex-col lg:flex-row gap-8">
          {/* Cart Items */}
          <section className="lg:w-[70%]">
            <div className="bg-white p-6 md:p-8 rounded-xl shadow-sm">
              <h1 className="text-3xl font-extrabold text-brand-900 mb-2 font-[family-name:var(--font-headline)]">{t('cart.title')}</h1>
              <p className="text-secondary text-sm border-b border-outline-variant/20 pb-4">
                {t('cart.items', { count: itemCount })}
              </p>
              {cartItems.map((item) => (
                <CartItem
                  key={item.productId}
                  item={item}
                  onUpdateQuantity={handleUpdateQuantity}
                  onRemove={handleRemove}
                />
              ))}
            </div>
          </section>

          {/* Checkout Sidebar */}
          <aside className="lg:w-[30%]">
            <div className="bg-white p-6 rounded-xl shadow-lg border-t-4 border-brand-500 sticky top-20">
              <p className="text-lg font-medium text-on-surface">
                {t('cart.subtotal', { count: itemCount })}
              </p>
              <p className="text-3xl font-extrabold text-brand-900 font-[family-name:var(--font-headline)] mt-1 mb-6">
                {formatPrice(subtotal)}
              </p>

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
                className="block w-full py-4 bg-brand-500 hover:bg-brand-700 text-white font-bold rounded-md shadow-md text-center transition-all uppercase tracking-wider text-sm font-[family-name:var(--font-headline)]"
              >
                {t('cart.checkout')}
              </Link>

              <Link
                to="/products"
                className="block w-full text-center text-secondary hover:text-brand-500 mt-4 text-sm transition-colors"
              >
                {t('cart.continue')}
              </Link>
            </div>

            {/* Rewards Card */}
            <div className="bg-brand-900 p-6 rounded-xl text-white mt-6">
              <h3 className="font-bold text-lg mb-2 font-[family-name:var(--font-headline)]">{t('cart.rewards')}</h3>
              <p className="text-sm text-white/70 mb-4">
                {t('cart.rewardsDesc')}
              </p>
              <a href="#" className="text-brand-300 text-sm font-bold hover:underline">{t('cart.learnMore')}</a>
            </div>
          </aside>
        </div>
      )}
    </div>
  );
}
