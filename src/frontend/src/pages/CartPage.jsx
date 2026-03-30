import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useCart } from '../context/CartContext';
import CartItem from '../components/CartItem';
import { api } from '../api';

export default function CartPage() {
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
        console.error('데이터를 불러올 수 없습니다:', error);
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
      console.error('수량 변경 실패:', error);
    }
  };

  const handleRemove = async (productId) => {
    const newItems = cartItems.filter(item => item.productId !== productId);
    setCartItems(newItems);
    updateCartCount(newItems.reduce((sum, item) => sum + item.quantity, 0));
    try {
      await api(`/carts/${user.id}/items/${productId}`, { method: 'DELETE' });
    } catch (error) {
      console.error('장바구니 삭제 실패:', error);
    }
  };

  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };

  const subtotal = cartItems.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const shippingFee = subtotal >= 50000 ? 0 : 3000;
  const total = subtotal + shippingFee;

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-slate-500 text-lg">로딩 중...</p>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold text-slate-800 mb-8">장바구니</h1>

      {cartItems.length === 0 ? (
        <div className="text-center py-16">
          <svg className="w-24 h-24 text-slate-300 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-8 2a2 2 0 11-4 0 2 2 0 014 0z" />
          </svg>
          <p className="text-slate-500 text-lg mb-4">장바구니가 비어있습니다.</p>
          <Link
            to="/products"
            className="inline-block bg-blue-500 text-white px-6 py-3 rounded-lg font-medium hover:bg-blue-600 transition-colors"
          >
            쇼핑 계속하기
          </Link>
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <div className="lg:col-span-2 space-y-4">
            {cartItems.map((item) => (
              <CartItem
                key={item.productId}
                item={item}
                onUpdateQuantity={handleUpdateQuantity}
                onRemove={handleRemove}
              />
            ))}
          </div>

          <div className="lg:col-span-1">
            <div className="bg-white rounded-lg shadow-sm p-6 sticky top-24">
              <h2 className="text-lg font-bold text-slate-800 mb-4">주문 요약</h2>

              <div className="space-y-3 mb-4">
                <div className="flex justify-between text-slate-600">
                  <span>상품 금액</span>
                  <span>{formatPrice(subtotal)}</span>
                </div>
                <div className="flex justify-between text-slate-600">
                  <span>배송비</span>
                  <span>{shippingFee === 0 ? '무료' : formatPrice(shippingFee)}</span>
                </div>
                {subtotal < 50000 && (
                  <p className="text-sm text-blue-500">
                    {formatPrice(50000 - subtotal)} 더 구매하시면 무료 배송!
                  </p>
                )}
              </div>

              <div className="border-t border-slate-200 pt-4 mb-6">
                <div className="flex justify-between text-lg font-bold text-slate-800">
                  <span>총 결제 금액</span>
                  <span className="text-blue-600">{formatPrice(total)}</span>
                </div>
              </div>

              <Link
                to="/checkout"
                className="block w-full bg-blue-500 text-white py-4 rounded-lg font-medium text-center hover:bg-blue-600 transition-colors"
              >
                주문하기
              </Link>

              <Link
                to="/products"
                className="block w-full text-center text-slate-500 hover:text-slate-700 mt-4"
              >
                쇼핑 계속하기
              </Link>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
