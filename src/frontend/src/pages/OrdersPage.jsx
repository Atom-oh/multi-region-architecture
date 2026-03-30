import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import OrderStatusBadge from '../components/OrderStatusBadge';
import { api, mapOrder } from '../api';

export default function OrdersPage() {
  const { user } = useAuth();
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchOrders = async () => {
      try {
        const data = await api(`/orders/user/${user.id}`);
        setOrders((data.orders || data || []).map(mapOrder));
      } catch (error) {
        console.error('데이터를 불러올 수 없습니다:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchOrders();
  }, [user?.id]);

  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };

  const formatDate = (dateString) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('ko-KR', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
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
      <h1 className="text-3xl font-bold text-slate-800 mb-8">주문 내역</h1>

      {orders.length === 0 ? (
        <div className="text-center py-16">
          <svg className="w-24 h-24 text-slate-300 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
          </svg>
          <p className="text-slate-500 text-lg mb-4">주문 내역이 없습니다.</p>
          <Link
            to="/products"
            className="inline-block bg-blue-500 text-white px-6 py-3 rounded-lg font-medium hover:bg-blue-600 transition-colors"
          >
            쇼핑하러 가기
          </Link>
        </div>
      ) : (
        <div className="space-y-6">
          {orders.map((order) => (
            <div key={order.id} className="bg-white rounded-lg shadow-sm overflow-hidden">
              <div className="p-4 bg-slate-50 border-b flex flex-wrap items-center justify-between gap-4">
                <div>
                  <p className="text-sm text-slate-500">주문번호</p>
                  <p className="font-medium text-slate-800">{order.id}</p>
                </div>
                <div>
                  <p className="text-sm text-slate-500">주문일</p>
                  <p className="font-medium text-slate-800">{formatDate(order.createdAt)}</p>
                </div>
                <div>
                  <OrderStatusBadge status={order.status} />
                </div>
              </div>

              <div className="p-4">
                <div className="space-y-3">
                  {order.items.map((item, index) => (
                    <div key={index} className="flex items-center gap-4">
                      <div className="w-16 h-16 bg-slate-100 rounded-lg overflow-hidden flex-shrink-0">
                        <img
                          src={`https://picsum.photos/seed/${order.id}-${index}/100/100`}
                          alt={item.name}
                          className="w-full h-full object-cover"
                        />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="font-medium text-slate-800 truncate">{item.name}</p>
                        <p className="text-sm text-slate-500">수량: {item.quantity}</p>
                      </div>
                      <p className="font-medium text-slate-800">
                        {formatPrice(item.price * item.quantity)}
                      </p>
                    </div>
                  ))}
                </div>

                <div className="flex items-center justify-between mt-4 pt-4 border-t">
                  <div>
                    <span className="text-slate-500">총 결제금액: </span>
                    <span className="text-lg font-bold text-blue-600">{formatPrice(order.total)}</span>
                  </div>
                  <div className="flex gap-2">
                    {order.status === 'shipping' && (
                      <Link
                        to={`/orders/${order.id}`}
                        className="px-4 py-2 bg-blue-500 text-white rounded-lg text-sm font-medium hover:bg-blue-600 transition-colors"
                      >
                        배송 조회
                      </Link>
                    )}
                    <Link
                      to={`/orders/${order.id}`}
                      className="px-4 py-2 border border-slate-300 rounded-lg text-sm font-medium text-slate-700 hover:bg-slate-50 transition-colors"
                    >
                      주문 상세
                    </Link>
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
