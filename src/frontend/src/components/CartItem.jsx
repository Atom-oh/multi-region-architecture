export default function CartItem({ item, onUpdateQuantity, onRemove }) {
  const formatPrice = (price) => {
    if (price == null) return '';
    return `$${(Number(price) / 100).toFixed(2)}`;
  };

  return (
    <div className="py-6 flex flex-col md:flex-row gap-6 border-b border-outline-variant/10 last:border-0">
      <div className="w-full md:w-40 h-40 bg-surface-low rounded-lg overflow-hidden flex-shrink-0">
        <img
          src={item.image || `https://picsum.photos/seed/${item.productId}/300/300`}
          alt={item.name}
          className="w-full h-full object-cover"
        />
      </div>

      <div className="flex-grow flex flex-col justify-between">
        <div>
          <div className="flex justify-between items-start">
            <h3 className="text-lg font-bold text-on-surface font-[family-name:var(--font-headline)] leading-tight">{item.name}</h3>
            <span className="text-lg font-bold text-brand-900 font-[family-name:var(--font-headline)] ml-4 whitespace-nowrap">
              {formatPrice(item.price * item.quantity)}
            </span>
          </div>
          <p className="text-sm text-secondary mt-1">{formatPrice(item.price)} each</p>
        </div>

        <div className="mt-4 flex flex-wrap items-center gap-4 text-sm font-medium">
          <div className="flex items-center bg-surface-container rounded-md px-2 py-1 border border-outline-variant/30">
            <label className="text-xs text-secondary mr-2">Qty:</label>
            <select
              value={item.quantity}
              onChange={(e) => onUpdateQuantity(item.productId, Number(e.target.value))}
              className="bg-transparent border-none focus:ring-0 text-sm py-0 pl-0 pr-6 cursor-pointer"
            >
              {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(n => (
                <option key={n} value={n}>{n}</option>
              ))}
            </select>
          </div>
          <div className="h-4 w-px bg-outline-variant/30 hidden md:block" />
          <button
            onClick={() => onRemove(item.productId)}
            className="text-brand-500 hover:underline decoration-2 underline-offset-4"
          >
            Delete
          </button>
          <button className="text-brand-500 hover:underline decoration-2 underline-offset-4">
            Save for later
          </button>
        </div>
      </div>
    </div>
  );
}
