export default function CartItem({ item, onUpdateQuantity, onRemove }) {
  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };

  return (
    <div className="flex gap-4 p-4 bg-white rounded-lg shadow-sm">
      <div className="w-24 h-24 bg-slate-100 rounded-lg overflow-hidden flex-shrink-0">
        <img
          src={item.image || `https://picsum.photos/seed/${item.productId}/200/200`}
          alt={item.name}
          className="w-full h-full object-cover"
        />
      </div>

      <div className="flex-1 min-w-0">
        <h3 className="font-medium text-slate-800 truncate">{item.name}</h3>
        <p className="text-lg font-bold text-blue-600 mt-1">{formatPrice(item.price)}</p>

        <div className="flex items-center gap-2 mt-2">
          <button
            onClick={() => onUpdateQuantity(item.productId, Math.max(1, item.quantity - 1))}
            className="w-8 h-8 rounded-full bg-slate-100 hover:bg-slate-200 flex items-center justify-center transition-colors"
          >
            -
          </button>
          <span className="w-8 text-center font-medium">{item.quantity}</span>
          <button
            onClick={() => onUpdateQuantity(item.productId, item.quantity + 1)}
            className="w-8 h-8 rounded-full bg-slate-100 hover:bg-slate-200 flex items-center justify-center transition-colors"
          >
            +
          </button>
        </div>
      </div>

      <div className="flex flex-col items-end justify-between">
        <button
          onClick={() => onRemove(item.productId)}
          className="text-slate-400 hover:text-red-500 transition-colors"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
        <p className="text-lg font-bold text-slate-800">
          {formatPrice(item.price * item.quantity)}
        </p>
      </div>
    </div>
  );
}
