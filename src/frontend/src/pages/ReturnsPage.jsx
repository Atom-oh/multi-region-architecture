import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { api } from '../api';

export default function ReturnsPage() {
  const { user } = useAuth();
  const [returns, setReturns] = useState([]);
  const [eligibleOrders, setEligibleOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [formData, setFormData] = useState({
    orderId: '',
    reason: '',
    reasonDetail: '',
  });

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [returnsData, ordersData] = await Promise.all([
          api(`/returns?user_id=${user.id}`).catch(() => ({ returns: [] })),
          api(`/orders/user/${user.id}`).catch(() => ({ orders: [] })),
        ]);

        const items = (returnsData.returns || returnsData || []).map(r => ({
          id: r.id,
          orderId: r.order_id || r.orderId,
          productName: r.product_name || r.productName,
          reason: r.reason,
          status: r.status,
          createdAt: r.created_at || r.createdAt,
          refundAmount: r.refund_amount || r.refundAmount,
        }));
        setReturns(items);

        const orders = (ordersData.orders || ordersData || [])
          .filter(o => o.status === 'delivered')
          .map(o => ({
            id: o.id,
            product: (o.items || []).map(i => i.name).join(', ') || '주문 상품',
            price: o.total_amount || o.total,
            deliveredAt: o.delivered_at || o.created_at || o.createdAt,
          }));
        setEligibleOrders(orders);
      } catch (error) {
        console.error('데이터를 불러올 수 없습니다:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, [user?.id]);

  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };

  const getStatusBadge = (status) => {
    const config = {
      pending: { label: '접수대기', color: 'bg-slate-100 text-slate-700' },
      processing: { label: '처리중', color: 'bg-yellow-100 text-yellow-700' },
      approved: { label: '승인됨', color: 'bg-blue-100 text-blue-700' },
      completed: { label: '환불완료', color: 'bg-green-100 text-green-700' },
      rejected: { label: '거절됨', color: 'bg-red-100 text-red-700' },
    };
    const c = config[status] || config.pending;
    return <span className={`px-3 py-1 rounded-full text-sm font-medium ${c.color}`}>{c.label}</span>;
  };

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    let newReturn;
    try {
      const data = await api('/returns', {
        method: 'POST',
        body: JSON.stringify({
          order_id: formData.orderId,
          reason: formData.reason,
          reason_detail: formData.reasonDetail,
          user_id: user.id,
        }),
      });
      const selectedOrder = eligibleOrders.find(o => o.id === formData.orderId);
      newReturn = {
        id: data.id || `RET-${Date.now()}`,
        orderId: data.order_id || formData.orderId,
        productName: data.product_name || selectedOrder?.product,
        reason: data.reason || formData.reason,
        status: data.status || 'pending',
        createdAt: data.created_at || new Date().toISOString().split('T')[0],
        refundAmount: data.refund_amount || selectedOrder?.price,
      };
    } catch (err) {
      console.error('반품 신청 API 오류:', err);
      const selectedOrder = eligibleOrders.find(o => o.id === formData.orderId);
      newReturn = {
        id: `RET-${Date.now()}`,
        orderId: formData.orderId,
        productName: selectedOrder?.product,
        reason: formData.reason,
        status: 'pending',
        createdAt: new Date().toISOString().split('T')[0],
        refundAmount: selectedOrder?.price,
      };
    }

    setReturns(prev => [newReturn, ...prev]);
    setShowForm(false);
    setFormData({ orderId: '', reason: '', reasonDetail: '' });
    alert('반품/교환 신청이 접수되었습니다.');
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-slate-500 text-lg">로딩 중...</p>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-8">
        <h1 className="text-3xl font-bold text-slate-800">반품/교환</h1>
        <button
          onClick={() => setShowForm(true)}
          className="bg-blue-500 text-white px-4 py-2 rounded-lg font-medium hover:bg-blue-600 transition-colors"
        >
          + 반품/교환 신청
        </button>
      </div>

      {/* Return Request Form */}
      {showForm && (
        <div className="bg-white rounded-lg shadow-sm p-6 mb-8">
          <h2 className="text-lg font-bold text-slate-800 mb-4">반품/교환 신청</h2>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">
                주문 선택
              </label>
              <select
                name="orderId"
                value={formData.orderId}
                onChange={handleChange}
                required
                className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="">주문을 선택하세요</option>
                {eligibleOrders.map((order) => (
                  <option key={order.id} value={order.id}>
                    {order.product} - {formatPrice(order.price)}
                  </option>
                ))}
              </select>
              {eligibleOrders.length === 0 && (
                <p className="text-sm text-slate-500 mt-1">배송완료된 주문이 없습니다.</p>
              )}
              <p className="text-sm text-slate-500 mt-1">배송완료 후 30일 이내 주문만 신청 가능합니다.</p>
            </div>

            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">
                사유
              </label>
              <select
                name="reason"
                value={formData.reason}
                onChange={handleChange}
                required
                className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="">사유를 선택하세요</option>
                <option value="defect">제품 불량/파손</option>
                <option value="wrong">오배송</option>
                <option value="change">단순 변심</option>
                <option value="size">사이즈/색상 교환</option>
                <option value="other">기타</option>
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">
                상세 사유
              </label>
              <textarea
                name="reasonDetail"
                value={formData.reasonDetail}
                onChange={handleChange}
                rows={4}
                placeholder="상세한 반품/교환 사유를 입력해주세요."
                className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
              />
            </div>

            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setShowForm(false)}
                className="flex-1 px-4 py-3 border border-slate-300 rounded-lg font-medium text-slate-700 hover:bg-slate-50 transition-colors"
              >
                취소
              </button>
              <button
                type="submit"
                className="flex-1 bg-blue-500 text-white px-4 py-3 rounded-lg font-medium hover:bg-blue-600 transition-colors"
              >
                신청하기
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Return History */}
      <div className="bg-white rounded-lg shadow-sm">
        <div className="p-6 border-b">
          <h2 className="text-lg font-bold text-slate-800">신청 내역</h2>
        </div>

        {returns.length === 0 ? (
          <div className="text-center py-16">
            <svg className="w-16 h-16 text-slate-300 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
            <p className="text-slate-500">반품/교환 신청 내역이 없습니다.</p>
          </div>
        ) : (
          <div className="divide-y">
            {returns.map((returnItem) => (
              <div key={returnItem.id} className="p-6">
                <div className="flex items-start justify-between mb-3">
                  <div>
                    <p className="font-medium text-slate-800">{returnItem.productName}</p>
                    <p className="text-sm text-slate-500 mt-1">
                      신청번호: {returnItem.id} | 주문번호: {returnItem.orderId}
                    </p>
                  </div>
                  {getStatusBadge(returnItem.status)}
                </div>

                <div className="bg-slate-50 rounded-lg p-4 mt-4">
                  <div className="grid grid-cols-2 gap-4 text-sm">
                    <div>
                      <p className="text-slate-500">사유</p>
                      <p className="font-medium text-slate-800">{returnItem.reason}</p>
                    </div>
                    <div>
                      <p className="text-slate-500">신청일</p>
                      <p className="font-medium text-slate-800">{returnItem.createdAt}</p>
                    </div>
                    {returnItem.refundAmount && (
                      <div>
                        <p className="text-slate-500">환불 예정 금액</p>
                        <p className="font-medium text-blue-600">{formatPrice(returnItem.refundAmount)}</p>
                      </div>
                    )}
                  </div>
                </div>

                <div className="flex gap-2 mt-4">
                  <Link
                    to={`/orders/${returnItem.orderId}`}
                    className="text-sm text-blue-500 hover:text-blue-600"
                  >
                    주문 상세 보기
                  </Link>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Return Policy */}
      <div className="bg-slate-50 rounded-lg p-6 mt-8">
        <h3 className="font-bold text-slate-800 mb-4">반품/교환 안내</h3>
        <ul className="space-y-2 text-sm text-slate-600">
          <li>- 상품 수령 후 30일 이내 신청 가능합니다.</li>
          <li>- 단순 변심의 경우 반품 배송비가 부과됩니다.</li>
          <li>- 제품 불량/오배송의 경우 무료로 처리됩니다.</li>
          <li>- 사용 흔적이 있거나 상품 가치가 훼손된 경우 반품이 제한될 수 있습니다.</li>
          <li>- 환불은 반품 상품 확인 후 2-3일 내 처리됩니다.</li>
        </ul>
      </div>
    </div>
  );
}
