export default function OrderStatusBadge({ status }) {
  const statusConfig = {
    pending: { label: '주문접수', color: 'bg-slate-100 text-slate-700' },
    processing: { label: '처리중', color: 'bg-yellow-100 text-yellow-700' },
    confirmed: { label: '주문확인', color: 'bg-blue-100 text-blue-700' },
    shipping: { label: '배송중', color: 'bg-indigo-100 text-indigo-700' },
    shipped: { label: '배송중', color: 'bg-indigo-100 text-indigo-700' },
    delivered: { label: '배송완료', color: 'bg-green-100 text-green-700' },
    cancelled: { label: '취소됨', color: 'bg-red-100 text-red-700' },
    returned: { label: '반품완료', color: 'bg-orange-100 text-orange-700' },
  };

  const config = statusConfig[status] || statusConfig.pending;

  return (
    <span className={`inline-block px-3 py-1 rounded-full text-sm font-medium ${config.color}`}>
      {config.label}
    </span>
  );
}
