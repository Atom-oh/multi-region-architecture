import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import { api, mapProduct } from '../api';
import { useI18n } from '../context/I18nContext';

export default function ProductDetailPage() {
  const { t } = useI18n();
  const { id } = useParams();
  const { user } = useAuth();
  const { incrementCart } = useCart();
  const [product, setProduct] = useState(null);
  const [reviews, setReviews] = useState([]);
  const [similarProducts, setSimilarProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [quantity, setQuantity] = useState(1);
  const [activeThumb, setActiveThumb] = useState(0);

  useEffect(() => {
    const fetchProduct = async () => {
      setLoading(true);
      try {
        const [productRes, reviewsRes, similarRes] = await Promise.all([
          api(`/products/${id}`),
          api(`/reviews/product/${id}`).catch(() => ({ reviews: [] })),
          api(`/recommendations/similar/${id}`).catch(() => ({ products: [] })),
        ]);

        if (productRes) {
          setProduct(mapProduct(productRes));
        }

        const revs = (reviewsRes.reviews || []).map(r => ({
          id: r.id || r._id,
          userName: r.user_name || r.userName,
          rating: r.rating,
          content: r.body || r.content,
          createdAt: r.created_at || r.createdAt,
        }));
        setReviews(revs);

        const similar = (similarRes.products || similarRes.similar || []).map(mapProduct);
        setSimilarProducts(similar);
      } catch (error) {
        console.error('Failed to load product:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchProduct();
    setActiveThumb(0);
    setQuantity(1);
  }, [id]);

  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };

  const renderStars = (rating) => {
    const full = Math.floor(rating || 0);
    const hasHalf = (rating || 0) % 1 >= 0.5;
    const empty = 5 - full - (hasHalf ? 1 : 0);
    return (
      <span className="inline-flex items-center gap-0.5 text-brand-500">
        {[...Array(full)].map((_, i) => (
          <span key={`f${i}`} className="material-symbols-outlined text-[18px]" style={{ fontVariationSettings: "'FILL' 1" }}>star</span>
        ))}
        {hasHalf && <span className="material-symbols-outlined text-[18px]">star_half</span>}
        {[...Array(empty)].map((_, i) => (
          <span key={`e${i}`} className="material-symbols-outlined text-[18px] text-outline-variant">star</span>
        ))}
      </span>
    );
  };

  const handleAddToCart = async () => {
    try {
      if (user?.id) {
        await api(`/carts/${user.id}`, {
          method: 'POST',
          body: JSON.stringify({
            product_id: product.id,
            name: product.name,
            quantity,
            price: product.price,
          }),
        });
      }
      for (let i = 0; i < quantity; i++) {
        incrementCart();
      }
      alert(t('detail.addedToCart', { name: product.name, qty: quantity }));
    } catch (err) {
      alert(err.message || t('detail.addToCartFailed'));
    }
  };

  const handleAddToWishlist = async () => {
    if (!user?.id) return;
    try {
      await api(`/wishlists/${user.id}/items`, {
        method: 'POST',
        body: JSON.stringify({ product_id: product.id }),
      });
      alert(t('detail.addedToWishlist', { name: product.name }));
    } catch (err) {
      alert(err.message || t('detail.wishlistFailed'));
    }
  };

  // Generate thumbnail URLs
  const thumbImages = product
    ? [0, 1, 2, 3].map(i => product.imageUrl || `https://picsum.photos/seed/${product.id}-${i}/400/400`)
    : [];

  // Generate urgency countdown (static demo)
  const urgencyHours = 14;
  const urgencyMinutes = 32;

  // Delivery date (3 days from now)
  const deliveryDate = new Date(Date.now() + 3 * 86400000).toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  });

  // Sentiment analysis data (demo)
  const sentimentBars = [
    { label: 'Quality', pct: 92 },
    { label: 'Value', pct: 85 },
    { label: 'Design', pct: 88 },
    { label: 'Durability', pct: 78 },
  ];

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="flex items-center gap-3 text-secondary">
          <span className="material-symbols-outlined animate-spin">progress_activity</span>
          <p className="text-lg">{t('common.loading')}</p>
        </div>
      </div>
    );
  }

  if (!product) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-secondary text-lg">Product not found.</p>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-4 py-6">
      {/* ============ Breadcrumb ============ */}
      <nav className="flex items-center gap-1.5 text-sm text-secondary mb-6">
        <Link to="/" className="hover:text-brand-500 transition-colors">Home</Link>
        <span className="material-symbols-outlined text-[14px] text-outline-variant">chevron_right</span>
        <Link to="/products" className="hover:text-brand-500 transition-colors">Products</Link>
        <span className="material-symbols-outlined text-[14px] text-outline-variant">chevron_right</span>
        <span className="text-on-surface font-medium truncate max-w-[200px]">{product.name}</span>
      </nav>

      {/* ============ 12-column Product Grid ============ */}
      <div className="grid grid-cols-12 gap-4 mb-16">
        {/* Thumbnails (1 col) */}
        <div className="col-span-1 hidden md:flex flex-col gap-2">
          {thumbImages.map((src, i) => (
            <button
              key={i}
              onClick={() => setActiveThumb(i)}
              className={`w-16 h-16 rounded-md overflow-hidden border-2 transition-colors ${
                i === activeThumb ? 'border-brand-500' : 'border-transparent hover:border-outline-variant'
              }`}
            >
              <img src={src} alt="" className="w-full h-full object-cover" />
            </button>
          ))}
        </div>

        {/* Main Image (5 col) */}
        <div className="col-span-12 md:col-span-5 aspect-square bg-surface-container rounded-xl overflow-hidden">
          <img
            src={thumbImages[activeThumb]}
            alt={product.name}
            className="w-full h-full object-contain"
          />
        </div>

        {/* Product Specs (3 col) */}
        <div className="col-span-12 md:col-span-3">
          <h1 className="text-xl font-bold text-on-surface font-[family-name:var(--font-headline)] mb-1 leading-tight">
            {product.name}
          </h1>
          <p className="text-sm mb-3">
            by{' '}
            <Link to="/products" className="text-brand-500 hover:text-brand-700 hover:underline">
              VELLURE
            </Link>
          </p>

          {/* Rating */}
          <div className="flex items-center gap-2 mb-3">
            {renderStars(product.rating)}
            <span className="text-sm text-brand-500 hover:text-brand-700 cursor-pointer">
              {product.reviewCount || 0} ratings
            </span>
          </div>

          <hr className="border-outline-variant/30 mb-4" />

          {/* Specs table */}
          <table className="w-full text-sm mb-5">
            <tbody>
              {[
                ['Brand', product.brand || 'VELLURE'],
                ['Color', 'Midnight Black'],
                ['Material', 'Premium'],
                ['Dimensions', '12 x 8 x 4 in'],
              ].map(([label, value]) => (
                <tr key={label} className="border-b border-outline-variant/20">
                  <td className="py-2 pr-4 font-semibold text-on-surface whitespace-nowrap">{label}</td>
                  <td className="py-2 text-on-surface-variant">{value}</td>
                </tr>
              ))}
            </tbody>
          </table>

          {/* Core Features */}
          <h3 className="font-bold text-on-surface text-sm mb-2 font-[family-name:var(--font-headline)]">
            Core Features
          </h3>
          <ul className="space-y-2">
            {[
              'Premium build quality',
              'Ergonomic design',
              'Sustainable materials',
              'Two-year warranty',
            ].map((feat) => (
              <li key={feat} className="flex items-start gap-2 text-sm text-on-surface-variant">
                <span className="material-symbols-outlined text-brand-500 text-[18px] mt-0.5" style={{ fontVariationSettings: "'FILL' 1" }}>
                  check_circle
                </span>
                {feat}
              </li>
            ))}
          </ul>
        </div>

        {/* Buy Box (3 col) */}
        <div className="col-span-12 md:col-span-3">
          <div className="border border-outline-variant/30 rounded-xl p-5 sticky top-24">
            {/* Price */}
            <p className="text-3xl font-bold text-on-surface mb-1 font-[family-name:var(--font-headline)]">
              {formatPrice(product.price)}
            </p>

            {/* Urgency */}
            <p className="text-sm text-red-600 font-semibold mb-3">
              <span className="material-symbols-outlined text-[14px] align-middle mr-0.5">timer</span>
              Ends in {urgencyHours}h {urgencyMinutes}m
            </p>

            {/* Free returns */}
            <p className="text-sm text-on-surface-variant mb-1">
              <span className="text-brand-500 font-semibold">FREE Returns</span>
            </p>

            {/* Delivery */}
            <p className="text-sm text-on-surface-variant mb-4">
              FREE delivery{' '}
              <span className="font-bold text-on-surface">{deliveryDate}</span>
            </p>

            {/* In stock */}
            <p className="text-sm font-bold text-green-700 mb-4">In Stock</p>

            {/* Quantity selector */}
            <div className="flex items-center gap-2 mb-4">
              <label className="text-sm text-on-surface font-medium">{t('common.qty')}</label>
              <select
                value={quantity}
                onChange={(e) => setQuantity(Number(e.target.value))}
                className="border border-outline-variant rounded-lg px-3 py-1.5 text-sm bg-surface-low focus:outline-none focus:ring-2 focus:ring-brand-500"
              >
                {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(n => (
                  <option key={n} value={n}>{n}</option>
                ))}
              </select>
            </div>

            {/* Add to Cart */}
            <button
              onClick={handleAddToCart}
              className="w-full bg-brand-500 hover:bg-brand-600 text-white py-2.5 rounded-full font-bold text-sm transition-colors mb-2 shadow-sm"
            >
              {t('detail.addToCart')}
            </button>

            {/* Buy Now */}
            <Link
              to="/checkout"
              className="block w-full text-center bg-brand-300 hover:bg-brand-200 text-brand-900 py-2.5 rounded-full font-bold text-sm transition-colors mb-4 shadow-sm"
            >
              Buy Now
            </Link>

            {/* Meta info */}
            <div className="space-y-2 text-xs text-secondary border-t border-outline-variant/30 pt-3">
              <div className="flex items-center gap-2">
                <span className="material-symbols-outlined text-[14px]">lock</span>
                Secure transaction
              </div>
              <div className="flex items-center gap-2">
                <span className="material-symbols-outlined text-[14px]">local_shipping</span>
                Ships from VELLURE
              </div>
              <div className="flex items-center gap-2">
                <span className="material-symbols-outlined text-[14px]">storefront</span>
                Sold by VELLURE
              </div>
            </div>

            {/* Add to List */}
            <button
              onClick={handleAddToWishlist}
              className="mt-4 w-full py-2 text-sm font-semibold text-on-surface border border-outline-variant/50 rounded-lg hover:bg-surface-low transition-colors"
            >
              {t('detail.addToWishlist')}
            </button>
          </div>
        </div>
      </div>

      {/* ============ Frequently Bought Together ============ */}
      {similarProducts.length >= 2 && (
        <section className="mb-16">
          <h2 className="text-xl font-bold text-on-surface font-[family-name:var(--font-headline)] mb-6">
            Frequently bought together
          </h2>
          <div className="flex items-center gap-3 flex-wrap">
            {/* Current product + 2 similar */}
            {[product, ...similarProducts.slice(0, 2)].map((p, idx) => (
              <div key={p.id + '-' + idx} className="flex items-center gap-3">
                {idx > 0 && (
                  <span className="text-3xl text-outline-variant font-light">+</span>
                )}
                <Link
                  to={`/products/${p.id}`}
                  className="w-36 h-36 rounded-lg overflow-hidden border border-outline-variant/30 bg-surface-container hover:border-brand-500 transition-colors"
                >
                  <img
                    src={p.imageUrl || `https://picsum.photos/seed/${p.id}/300/300`}
                    alt={p.name}
                    className="w-full h-full object-cover"
                  />
                </Link>
              </div>
            ))}

            {/* Price total & CTA */}
            <div className="ml-6">
              <p className="text-sm text-secondary mb-1">Total price:</p>
              <p className="text-2xl font-bold text-on-surface font-[family-name:var(--font-headline)] mb-3">
                {formatPrice(
                  (product.price || 0) +
                  (similarProducts[0]?.price || 0) +
                  (similarProducts[1]?.price || 0)
                )}
              </p>
              <button className="bg-brand-500 hover:bg-brand-600 text-white px-6 py-2 rounded-full text-sm font-bold transition-colors shadow-sm">
                Add all three to Cart
              </button>
            </div>
          </div>
        </section>
      )}

      {/* ============ Customer Reviews ============ */}
      <section className="mb-16">
        <h2 className="text-xl font-bold text-on-surface font-[family-name:var(--font-headline)] mb-6">
          {t('detail.reviews')}
        </h2>

        {reviews.length === 0 ? (
          <p className="text-secondary py-4">{t('detail.noReviews')}</p>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-12 gap-5">
            {/* Featured review (wider) */}
            <div className="md:col-span-5 bg-white rounded-xl border border-outline-variant/20 p-6 shadow-sm">
              <div className="flex items-center gap-3 mb-3">
                <div className="w-10 h-10 bg-brand-300 rounded-full flex items-center justify-center">
                  <span className="text-sm font-bold text-brand-900">
                    {(reviews[0]?.userName || 'A').charAt(0).toUpperCase()}
                  </span>
                </div>
                <div>
                  <p className="font-bold text-on-surface text-sm">{reviews[0]?.userName || 'Anonymous'}</p>
                  <p className="text-xs text-secondary">Verified Purchase</p>
                </div>
              </div>
              <div className="mb-2">{renderStars(reviews[0]?.rating || 5)}</div>
              <p className="text-sm text-on-surface-variant leading-relaxed">
                {reviews[0]?.content || 'Great product with excellent quality.'}
              </p>
            </div>

            {/* Side reviews */}
            <div className="md:col-span-4 space-y-4">
              {reviews.slice(1, 3).map((review) => (
                <div key={review.id} className="bg-white rounded-xl border border-outline-variant/20 p-5 shadow-sm">
                  <div className="flex items-center gap-2 mb-2">
                    <div className="w-8 h-8 bg-surface-high rounded-full flex items-center justify-center">
                      <span className="text-xs font-bold text-on-surface-variant">
                        {(review.userName || 'A').charAt(0).toUpperCase()}
                      </span>
                    </div>
                    <p className="font-bold text-on-surface text-sm">{review.userName || 'Anonymous'}</p>
                  </div>
                  <div className="mb-1.5">{renderStars(review.rating)}</div>
                  <p className="text-sm text-on-surface-variant leading-relaxed line-clamp-3">
                    {review.content}
                  </p>
                </div>
              ))}
            </div>

            {/* Sentiment Analysis dark card */}
            <div className="md:col-span-3 bg-brand-900 rounded-xl p-5 text-white">
              <h3 className="text-sm font-bold text-brand-400 font-[family-name:var(--font-headline)] mb-1">
                Sentiment Analysis
              </h3>
              <p className="text-xs text-stone-400 mb-5">Based on {reviews.length} reviews</p>
              <div className="space-y-4">
                {sentimentBars.map(({ label, pct }) => (
                  <div key={label}>
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-xs text-stone-300">{label}</span>
                      <span className="text-xs font-bold text-brand-400">{pct}%</span>
                    </div>
                    <div className="w-full h-1.5 bg-white/10 rounded-full overflow-hidden">
                      <div
                        className="h-full bg-brand-500 rounded-full transition-all"
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </section>

      {/* ============ Similar Products ============ */}
      {similarProducts.length > 0 && (
        <section className="mb-16">
          <h2 className="text-xl font-bold text-on-surface font-[family-name:var(--font-headline)] mb-6">
            {t('detail.similar')}
          </h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            {similarProducts.slice(0, 4).map((p) => (
              <Link
                key={p.id}
                to={`/products/${p.id}`}
                className="bg-white rounded-xl overflow-hidden border border-outline-variant/20 hover:shadow-lg transition-all group block"
              >
                <div className="aspect-square bg-surface-container overflow-hidden">
                  <img
                    src={p.imageUrl || `https://picsum.photos/seed/${p.id}/400/400`}
                    alt={p.name}
                    className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                  />
                </div>
                <div className="p-4">
                  <h3 className="font-bold text-on-surface text-sm truncate mb-1 font-[family-name:var(--font-headline)]">
                    {p.name}
                  </h3>
                  <div className="flex items-center gap-1 mb-1">
                    {renderStars(p.rating || 4)}
                    <span className="text-xs text-secondary">({p.reviewCount || 0})</span>
                  </div>
                  <p className="font-bold text-brand-900 font-[family-name:var(--font-headline)]">
                    {formatPrice(p.price)}
                  </p>
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
