import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import OrderStatusBadge from '../components/OrderStatusBadge';
import { api } from '../api';

export default function OrderDetailPage() {
  const { id } = useParams();
  const [order, setOrder] = useState(null);
  const [tracking, setTracking] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchOrder = async () => {
      try {
        const orderData = await api(`/orders/${id}`);
        const shippingAddr = orderData.shipping_address || {};
        const addressParts = [shippingAddr.city, shippingAddr.district, shippingAddr.street].filter(Boolean);
        setOrder({
          id: orderData.id,
          createdAt: orderData.created_at || orderData.createdAt,
          status: orderData.status,
          items: (orderData.items || []).map(i => ({
            productId: i.product_id || i.productId,
            name: i.name,
            quantity: i.quantity,
            price: i.price,
          })),
          subtotal: orderData.subtotal || orderData.total_amount,
          shippingFee: orderData.shipping_fee || 0,
          total: orderData.total_amount || orderData.total,
          shipping: {
            name: shippingAddr.name || '',
            phone: shippingAddr.phone || '',
            address: addressParts.length > 0 ? addressParts.join(' ') : (shippingAddr.address || ''),
            addressDetail: shippingAddr.zip || shippingAddr.address_detail || '',
          },
          payment: {
            method: orderData.payment_method || '신용카드',
            cardNumber: '**** **** **** 1234',
          },
          trackingNumber: orderData.tracking_number || '',
          carrier: orderData.carrier || '',
        });

        try {
          const shipData = await api(`/shipments/order/${id}`);
          const shipment = Array.isArray(shipData) ? shipData[0] : shipData;
          const events = (shipment?.events || shipment?.tracking_events || []).map(e => ({
            status: e.status,
            message: e.message || e.description,
            time: e.time || e.timestamp,
            completed: e.completed !== undefined ? e.completed : true,
          }));
          setTracking(events);
        } catch {
          setTracking([]);
        }
      } catch (error) {
        console.error('데이터를 불러올 수 없습니다:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchOrder();
  }, [id]);

  const formatPrice = (price) => {
    return `₩${price.toLocaleString('ko-KR')}`;
  };

  const formatDate = (dateString) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('ko-KR', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-slate-500 text-lg">로딩 중...</p>
      </div>
    );
  }

  if (!order) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-slate-500 text-lg">주문을 찾을 수 없습니다.</p>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      <nav className="text-sm text-slate-500 mb-6">
        <Link to="/" className="hover:text-blue-500">홈</Link>
        <span className="mx-2">/</span>
        <Link to="/orders" className="hover:text-blue-500">주문 내역</Link>
        <span className="mx-2">/</span>
        <span className="text-slate-800">{order.id}</span>
      </nav>

      <div className="flex items-center justify-between mb-8">
        <h1 className="text-3xl font-bold text-slate-800">주문 상세</h1>
        <OrderStatusBadge status={order.status} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2 space-y-6">
          {/* Order Items */}
          <div className="bg-white rounded-lg shadow-sm p-6">
            <h2 className="text-lg font-bold text-slate-800 mb-4">주문 상품</h2>
            <div className="space-y-4">
              {order.items.map((item) => (
                <div key={item.productId} className="flex items-center gap-4">
                  <div className="w-20 h-20 bg-slate-100 rounded-lg overflow-hidden flex-shrink-0">
                    <img
                      src={`https://picsum.photos/seed/${item.productId}/100/100`}
                      alt={item.name}
                      className="w-full h-full object-cover"
                    />
                  </div>
                  <div className="flex-1 min-w-0">
                    <Link
                      to={`/products/${item.productId}`}
                      className="font-medium text-slate-800 hover:text-blue-500"
                    >
                      {item.name}
                    </Link>
                    <p className="text-sm text-slate-500">수량: {item.quantity}</p>
                  </div>
                  <p className="font-bold text-slate-800">
                    {formatPrice(item.price * item.quantity)}
                  </p>
                </div>
              ))}
            </div>

            <div className="border-t border-slate-200 mt-4 pt-4 space-y-2">
              <div className="flex justify-between text-slate-600">
                <span>상품 금액</span>
                <span>{formatPrice(order.subtotal)}</span>
              </div>
              <div className="flex justify-between text-slate-600">
                <span>배송비</span>
                <span>{order.shippingFee === 0 ? '무료' : formatPrice(order.shippingFee)}</span>
              </div>
              <div className="flex justify-between text-lg font-bold text-slate-800 pt-2 border-t">
                <span>총 결제 금액</span>
                <span className="text-blue-600">{formatPrice(order.total)}</span>
              </div>
            </div>
          </div>

          {/* Tracking Timeline */}
          {tracking.length > 0 && (
            <div className="bg-white rounded-lg shadow-sm p-6">
              <h2 className="text-lg font-bold text-slate-800 mb-4">배송 추적</h2>
              {(order.carrier || order.trackingNumber) && (
                <div className="flex items-center gap-4 mb-6 p-4 bg-slate-50 rounded-lg">
                  {order.carrier && (
                    <div>
                      <p className="text-sm text-slate-500">택배사</p>
                      <p className="font-medium text-slate-800">{order.carrier}</p>
                    </div>
                  )}
                  {order.trackingNumber && (
                    <div>
                      <p className="text-sm text-slate-500">운송장 번호</p>
                      <p className="font-medium text-slate-800">{order.trackingNumber}</p>
                    </div>
                  )}
                </div>
              )}

              <div className="relative">
                {tracking.map((step, index) => (
                  <div key={index} className="flex gap-4 pb-6 last:pb-0">
                    <div className="relative">
                      <div
                        className={`w-4 h-4 rounded-full ${
                          step.completed ? 'bg-blue-500' : 'bg-slate-300'
                        }`}
                      />
                      {index < tracking.length - 1 && (
                        <div
                          className={`absolute top-4 left-1.5 w-1 h-full ${
                            step.completed ? 'bg-blue-500' : 'bg-slate-200'
                          }`}
                        />
                      )}
                    </div>
                    <div className="flex-1">
                      <p className={`font-medium ${step.completed ? 'text-slate-800' : 'text-slate-400'}`}>
                        {step.message}
                      </p>
                      <p className="text-sm text-slate-500">{step.time}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        <div className="lg:col-span-1 space-y-6">
          {/* Order Info */}
          <div className="bg-white rounded-lg shadow-sm p-6">
            <h2 className="text-lg font-bold text-slate-800 mb-4">주문 정보</h2>
            <div className="space-y-3 text-sm">
              <div>
                <p className="text-slate-500">주문번호</p>
                <p className="font-medium text-slate-800">{order.id}</p>
              </div>
              <div>
                <p className="text-slate-500">주문일시</p>
                <p className="font-medium text-slate-800">{formatDate(order.createdAt)}</p>
              </div>
            </div>
          </div>

          {/* Shipping Info */}
          <div className="bg-white rounded-lg shadow-sm p-6">
            <h2 className="text-lg font-bold text-slate-800 mb-4">배송지 정보</h2>
            <div className="space-y-3 text-sm">
              <div>
                <p className="text-slate-500">받는 분</p>
                <p className="font-medium text-slate-800">{order.shipping.name || '-'}</p>
              </div>
              <div>
                <p className="text-slate-500">연락처</p>
                <p className="font-medium text-slate-800">{order.shipping.phone || '-'}</p>
              </div>
              <div>
                <p className="text-slate-500">주소</p>
                <p className="font-medium text-slate-800">
                  {order.shipping.address || '-'}
                  {order.shipping.addressDetail && <><br />{order.shipping.addressDetail}</>}
                </p>
              </div>
            </div>
          </div>

          {/* Payment Info */}
          <div className="bg-white rounded-lg shadow-sm p-6">
            <h2 className="text-lg font-bold text-slate-800 mb-4">결제 정보</h2>
            <div className="space-y-3 text-sm">
              <div>
                <p className="text-slate-500">결제 수단</p>
                <p className="font-medium text-slate-800">{order.payment.method}</p>
              </div>
              <div>
                <p className="text-slate-500">카드 번호</p>
                <p className="font-medium text-slate-800">{order.payment.cardNumber}</p>
              </div>
            </div>
          </div>

          <Link
            to="/returns"
            className="block w-full text-center py-3 border border-slate-300 rounded-lg text-slate-700 font-medium hover:bg-slate-50 transition-colors"
          >
            반품/교환 신청
          </Link>
        </div>
      </div>
    </div>
  );
}
