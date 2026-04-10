import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useCart } from '../context/CartContext';
import { api } from '../api';
import { validatePhone, validateCardNumber, validateExpiry, validateCVC } from '../utils';
import { useI18n } from '../context/I18nContext';

export default function CheckoutPage() {
  const { t } = useI18n();
  const { user } = useAuth();
  const { updateCartCount } = useCart();
  const navigate = useNavigate();

  const [formData, setFormData] = useState({
    name: user?.name || '',
    phone: user?.phone || '',
    address: user?.address || '',
    addressDetail: '',
    paymentMethod: 'card',
    cardNumber: '',
    cardExpiry: '',
    cardCvc: '',
  });

  const [cartItems, setCartItems] = useState([]);
  const [isProcessing, setIsProcessing] = useState(false);

  useEffect(() => {
    const fetchCart = async () => {
      try {
        const data = await api(`/carts/${user.id}`);
        const items = (data.items || []).map(item => ({
          productId: item.product_id || item.productId,
          name: item.name,
          quantity: item.quantity,
          price: item.price,
        }));
        if (items.length > 0) setCartItems(items);
      } catch (error) {
        console.error('Failed to load cart:', error);
      }
    };
    fetchCart();
  }, [user?.id]);

  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };
  const subtotal = cartItems.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const shippingFee = subtotal >= 50000 ? 0 : 3000;
  const total = subtotal + shippingFee;

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
  };

  const [error, setError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    if (!formData.name || !formData.phone || !formData.address) {
      setError(t('checkout.fillFields'));
      return;
    }
    if (!validatePhone(formData.phone)) {
      setError(t('checkout.invalidPhone'));
      return;
    }
    if (formData.paymentMethod === 'card') {
      if (!validateCardNumber(formData.cardNumber)) {
        setError(t('checkout.invalidCard'));
        return;
      }
      if (!validateExpiry(formData.cardExpiry)) {
        setError(t('checkout.invalidExpiry'));
        return;
      }
      if (!validateCVC(formData.cardCvc)) {
        setError(t('checkout.invalidCvc'));
        return;
      }
    }

    setIsProcessing(true);
    try {
      const data = await api('/orders', {
        method: 'POST',
        body: JSON.stringify({
          user_id: user.id,
          items: cartItems.map(i => ({
            product_id: i.productId,
            name: i.name,
            quantity: i.quantity,
            price: i.price,
          })),
          total_amount: total,
          shipping_address: {
            name: formData.name,
            phone: formData.phone,
            address: formData.address,
            address_detail: formData.addressDetail,
          },
          payment_method: formData.paymentMethod,
        }),
      });

      // Clear cart on backend after successful order
      for (const item of cartItems) {
        try { await api(`/carts/${user.id}/items/${item.productId}`, { method: 'DELETE' }); } catch {}
      }
      updateCartCount(0);
      navigate(`/orders/${data.id || data.order_id}`);
    } catch (error) {
      setError(error.message || t('checkout.orderFailed'));
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold text-slate-800 mb-8">{t('checkout.title')}</h1>

      {cartItems.length === 0 ? (
        <p className="text-slate-500 text-center py-12">{t('checkout.emptyCart')}</p>
      ) : (
        <form onSubmit={handleSubmit}>
          {error && (
            <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg text-red-600 text-sm">{error}</div>
          )}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
            <div className="lg:col-span-2 space-y-6">
              {/* Shipping Info */}
              <div className="bg-white rounded-lg shadow-sm p-6">
                <h2 className="text-lg font-bold text-slate-800 mb-4">{t('checkout.shipping')}</h2>

                <div className="space-y-4">
                  <div>
                    <label className="block text-sm font-medium text-slate-700 mb-1">
                      {t('checkout.recipient')}
                    </label>
                    <input
                      type="text"
                      name="name"
                      value={formData.name}
                      onChange={handleChange}
                      required
                      className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-slate-700 mb-1">
                      {t('checkout.phone')}
                    </label>
                    <input
                      type="tel"
                      name="phone"
                      value={formData.phone}
                      onChange={handleChange}
                      required
                      placeholder="010-0000-0000"
                      className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-slate-700 mb-1">
                      {t('checkout.address')}
                    </label>
                    <input
                      type="text"
                      name="address"
                      value={formData.address}
                      onChange={handleChange}
                      required
                      className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-slate-700 mb-1">
                      {t('checkout.addressDetail')}
                    </label>
                    <input
                      type="text"
                      name="addressDetail"
                      value={formData.addressDetail}
                      onChange={handleChange}
                      className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                  </div>
                </div>
              </div>

              {/* Payment Method */}
              <div className="bg-white rounded-lg shadow-sm p-6">
                <h2 className="text-lg font-bold text-slate-800 mb-4">{t('checkout.payment')}</h2>

                <div className="space-y-3 mb-6">
                  <label className="flex items-center gap-3 p-3 border rounded-lg cursor-pointer hover:border-blue-500 transition-colors">
                    <input
                      type="radio"
                      name="paymentMethod"
                      value="card"
                      checked={formData.paymentMethod === 'card'}
                      onChange={handleChange}
                      className="w-4 h-4 text-blue-500"
                    />
                    <span className="font-medium">{t('checkout.card')}</span>
                  </label>

                  <label className="flex items-center gap-3 p-3 border rounded-lg cursor-pointer hover:border-blue-500 transition-colors">
                    <input
                      type="radio"
                      name="paymentMethod"
                      value="bank"
                      checked={formData.paymentMethod === 'bank'}
                      onChange={handleChange}
                      className="w-4 h-4 text-blue-500"
                    />
                    <span className="font-medium">{t('checkout.bank')}</span>
                  </label>

                  <label className="flex items-center gap-3 p-3 border rounded-lg cursor-pointer hover:border-blue-500 transition-colors">
                    <input
                      type="radio"
                      name="paymentMethod"
                      value="kakao"
                      checked={formData.paymentMethod === 'kakao'}
                      onChange={handleChange}
                      className="w-4 h-4 text-blue-500"
                    />
                    <span className="font-medium">{t('checkout.kakao')}</span>
                  </label>

                  <label className="flex items-center gap-3 p-3 border rounded-lg cursor-pointer hover:border-blue-500 transition-colors">
                    <input
                      type="radio"
                      name="paymentMethod"
                      value="naver"
                      checked={formData.paymentMethod === 'naver'}
                      onChange={handleChange}
                      className="w-4 h-4 text-blue-500"
                    />
                    <span className="font-medium">{t('checkout.naver')}</span>
                  </label>
                </div>

                {formData.paymentMethod === 'card' && (
                  <div className="space-y-4 pt-4 border-t">
                    <div>
                      <label className="block text-sm font-medium text-slate-700 mb-1">
                        {t('checkout.cardNumber')}
                      </label>
                      <input
                        type="text"
                        name="cardNumber"
                        value={formData.cardNumber}
                        onChange={handleChange}
                        placeholder="0000-0000-0000-0000"
                        className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                      />
                    </div>

                    <div className="grid grid-cols-2 gap-4">
                      <div>
                        <label className="block text-sm font-medium text-slate-700 mb-1">
                          {t('checkout.expiry')}
                        </label>
                        <input
                          type="text"
                          name="cardExpiry"
                          value={formData.cardExpiry}
                          onChange={handleChange}
                          placeholder="MM/YY"
                          className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                      </div>
                      <div>
                        <label className="block text-sm font-medium text-slate-700 mb-1">
                          {t('checkout.cvc')}
                        </label>
                        <input
                          type="text"
                          name="cardCvc"
                          value={formData.cardCvc}
                          onChange={handleChange}
                          placeholder="000"
                          className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* Order Summary */}
            <div className="lg:col-span-1">
              <div className="bg-white rounded-lg shadow-sm p-6 sticky top-24">
                <h2 className="text-lg font-bold text-slate-800 mb-4">{t('checkout.orderItems')}</h2>

                <div className="space-y-3 mb-4">
                  {cartItems.map((item) => (
                    <div key={item.productId} className="flex justify-between text-sm">
                      <span className="text-slate-600 truncate flex-1 mr-2">
                        {item.name} x {item.quantity}
                      </span>
                      <span className="text-slate-800 font-medium">
                        {formatPrice(item.price * item.quantity)}
                      </span>
                    </div>
                  ))}
                </div>

                <div className="border-t border-slate-200 pt-4 space-y-2 mb-4">
                  <div className="flex justify-between text-slate-600">
                    <span>{t('checkout.subtotal')}</span>
                    <span>{formatPrice(subtotal)}</span>
                  </div>
                  <div className="flex justify-between text-slate-600">
                    <span>{t('checkout.shippingFee')}</span>
                    <span>{shippingFee === 0 ? t('checkout.free') : formatPrice(shippingFee)}</span>
                  </div>
                </div>

                <div className="border-t border-slate-200 pt-4 mb-6">
                  <div className="flex justify-between text-lg font-bold text-slate-800">
                    <span>{t('checkout.total')}</span>
                    <span className="text-blue-600">{formatPrice(total)}</span>
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={isProcessing}
                  className="w-full bg-blue-500 text-white py-4 rounded-lg font-medium hover:bg-blue-600 transition-colors disabled:bg-slate-300 disabled:cursor-not-allowed"
                >
                  {isProcessing ? t('checkout.processing') : t('checkout.pay', { amount: formatPrice(total) })}
                </button>

                <p className="text-xs text-slate-500 text-center mt-4">
                  {t('checkout.agreement')}
                </p>
              </div>
            </div>
          </div>
        </form>
      )}
    </div>
  );
}
