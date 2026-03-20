import { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';

const MOCK_SELLER_DATA = {
  shopName: '김민수 스토어',
  totalSales: 15890000,
  monthSales: 3240000,
  totalOrders: 156,
  pendingOrders: 8,
  products: [
    { id: 'PRD-S001', name: '프리미엄 가죽 지갑', price: 89000, stock: 45, sales: 23 },
    { id: 'PRD-S002', name: '스테인리스 텀블러', price: 35000, stock: 120, sales: 67 },
    { id: 'PRD-S003', name: '무선 충전 패드', price: 29000, stock: 80, sales: 45 },
    { id: 'PRD-S004', name: '에코백 대형', price: 15000, stock: 200, sales: 134 },
  ],
  recentOrders: [
    { id: 'ORD-S001', product: '프리미엄 가죽 지갑', quantity: 2, total: 178000, status: 'pending', date: '2024-03-20' },
    { id: 'ORD-S002', product: '스테인리스 텀블러', quantity: 3, total: 105000, status: 'shipping', date: '2024-03-19' },
    { id: 'ORD-S003', product: '무선 충전 패드', quantity: 1, total: 29000, status: 'delivered', date: '2024-03-18' },
  ],
};

const ANALYTICS_DATA = [
  { label: '3월 1주', sales: 820000 },
  { label: '3월 2주', sales: 1150000 },
  { label: '3월 3주', sales: 980000 },
  { label: '3월 4주', sales: 1340000 },
];

export default function SellerDashboardPage() {
  const { user } = useAuth();
  const [sellerData, setSellerData] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchSellerData = async () => {
      try {
        await new Promise(resolve => setTimeout(resolve, 300));
        setSellerData(MOCK_SELLER_DATA);
      } catch (error) {
        console.error('데이터를 불러올 수 없습니다:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchSellerData();
  }, [user?.id]);

  const formatPrice = (price) => {
    return `₩${price.toLocaleString('ko-KR')}`;
  };

  const getStatusBadge = (status) => {
    const config = {
      pending: { label: '처리대기', color: 'bg-yellow-100 text-yellow-700' },
      shipping: { label: '배송중', color: 'bg-blue-100 text-blue-700' },
      delivered: { label: '배송완료', color: 'bg-green-100 text-green-700' },
    };
    const c = config[status] || config.pending;
    return <span className={`px-2 py-1 rounded-full text-xs font-medium ${c.color}`}>{c.label}</span>;
  };

  const maxSales = Math.max(...ANALYTICS_DATA.map(d => d.sales));

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-slate-500 text-lg">로딩 중...</p>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="text-3xl font-bold text-slate-800">판매자 대시보드</h1>
          <p className="text-slate-500 mt-1">{sellerData.shopName}</p>
        </div>
        <button className="bg-blue-500 text-white px-4 py-2 rounded-lg font-medium hover:bg-blue-600 transition-colors">
          + 새 상품 등록
        </button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <div className="bg-white rounded-lg shadow-sm p-6">
          <p className="text-slate-500 text-sm">총 매출</p>
          <p className="text-2xl font-bold text-slate-800 mt-1">{formatPrice(sellerData.totalSales)}</p>
        </div>
        <div className="bg-white rounded-lg shadow-sm p-6">
          <p className="text-slate-500 text-sm">이번 달 매출</p>
          <p className="text-2xl font-bold text-blue-600 mt-1">{formatPrice(sellerData.monthSales)}</p>
        </div>
        <div className="bg-white rounded-lg shadow-sm p-6">
          <p className="text-slate-500 text-sm">총 주문</p>
          <p className="text-2xl font-bold text-slate-800 mt-1">{sellerData.totalOrders}건</p>
        </div>
        <div className="bg-white rounded-lg shadow-sm p-6">
          <p className="text-slate-500 text-sm">처리 대기</p>
          <p className="text-2xl font-bold text-orange-500 mt-1">{sellerData.pendingOrders}건</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Analytics Chart */}
        <div className="lg:col-span-2 bg-white rounded-lg shadow-sm p-6">
          <h2 className="text-lg font-bold text-slate-800 mb-6">주간 매출 현황</h2>
          <div className="flex items-end justify-between gap-4 h-48">
            {ANALYTICS_DATA.map((data, index) => (
              <div key={index} className="flex-1 flex flex-col items-center">
                <div
                  className="w-full bg-blue-500 rounded-t-lg transition-all duration-500"
                  style={{ height: `${(data.sales / maxSales) * 100}%` }}
                />
                <p className="text-xs text-slate-500 mt-2">{data.label}</p>
                <p className="text-xs font-medium text-slate-700">{formatPrice(data.sales)}</p>
              </div>
            ))}
          </div>
        </div>

        {/* Recent Orders */}
        <div className="bg-white rounded-lg shadow-sm p-6">
          <h2 className="text-lg font-bold text-slate-800 mb-4">최근 주문</h2>
          <div className="space-y-4">
            {sellerData.recentOrders.map((order) => (
              <div key={order.id} className="border-b border-slate-100 pb-4 last:border-0 last:pb-0">
                <div className="flex items-center justify-between mb-1">
                  <p className="font-medium text-slate-800 text-sm truncate">{order.product}</p>
                  {getStatusBadge(order.status)}
                </div>
                <div className="flex items-center justify-between text-sm text-slate-500">
                  <span>{order.quantity}개</span>
                  <span>{formatPrice(order.total)}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Product List */}
      <div className="bg-white rounded-lg shadow-sm mt-8">
        <div className="p-6 border-b">
          <h2 className="text-lg font-bold text-slate-800">내 상품</h2>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-slate-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">상품명</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">가격</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">재고</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">판매량</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase">관리</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {sellerData.products.map((product) => (
                <tr key={product.id} className="hover:bg-slate-50">
                  <td className="px-6 py-4">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 bg-slate-100 rounded-lg overflow-hidden">
                        <img
                          src={`https://picsum.photos/seed/${product.id}/100/100`}
                          alt={product.name}
                          className="w-full h-full object-cover"
                        />
                      </div>
                      <span className="font-medium text-slate-800">{product.name}</span>
                    </div>
                  </td>
                  <td className="px-6 py-4 text-slate-600">{formatPrice(product.price)}</td>
                  <td className="px-6 py-4">
                    <span className={`font-medium ${product.stock < 50 ? 'text-orange-500' : 'text-slate-600'}`}>
                      {product.stock}개
                    </span>
                  </td>
                  <td className="px-6 py-4 text-slate-600">{product.sales}개</td>
                  <td className="px-6 py-4">
                    <div className="flex gap-2">
                      <button className="text-blue-500 hover:text-blue-600 text-sm font-medium">
                        수정
                      </button>
                      <button className="text-red-500 hover:text-red-600 text-sm font-medium">
                        삭제
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
