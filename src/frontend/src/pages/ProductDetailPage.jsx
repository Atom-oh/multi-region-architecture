import { useState, useEffect, useCallback } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import { api, mapProduct } from '../api';
import { useI18n } from '../context/I18nContext';
import StarRating from '../components/StarRating';
import ReviewForm from '../components/ReviewForm';

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
  const [activeImage, setActiveImage] = useState(0);
  const [imageZoom, setImageZoom] = useState(false);
  const [activeTab, setActiveTab] = useState('description');
  const [showReviewForm, setShowReviewForm] = useState(false);
  const [editingReview, setEditingReview] = useState(null);
  const [reviewSort, setReviewSort] = useState('newest');
  const [reviewPage, setReviewPage] = useState(1);
  const [reviewTotal, setReviewTotal] = useState(0);
  const [reviewHasMore, setReviewHasMore] = useState(false);
  const [votedReviews, setVotedReviews] = useState(() => {
    try { return JSON.parse(localStorage.getItem('votedReviews') || '[]'); } catch { return []; }
  });
  const [reviewMenuOpen, setReviewMenuOpen] = useState(null);

  const mapReview = (r) => ({
    id: r.id || r._id,
    userId: r.user_id || r.userId,
    userName: r.user_name || r.userName,
    rating: r.rating,
    content: r.body || r.content,
    createdAt: r.created_at || r.createdAt,
    images: r.images || [],
    verifiedPurchase: r.verified_purchase ?? r.verifiedPurchase ?? false,
    helpfulCount: r.helpful_count || r.helpfulCount || 0,
    title: r.title || '',
  });

  const fetchReviews = useCallback(async (page = 1, sort = 'newest', append = false) => {
    try {
      const res = await api(`/reviews/product/${id}?page=${page}&page_size=10&sort=${sort}`).catch(() => ({ reviews: [], total: 0, has_more: false }));
      const revs = (res.reviews || []).map(mapReview);
      setReviews(prev => append ? [...prev, ...revs] : revs);
      setReviewTotal(res.total || 0);
      setReviewHasMore(res.has_more ?? false);
    } catch {
      if (!append) setReviews([]);
    }
  }, [id]);

  useEffect(() => {
    const fetchProduct = async () => {
      setLoading(true);
      try {
        const [productRes, , similarRes] = await Promise.all([
          api(`/products/${id}`),
          fetchReviews(1, 'newest'),
          api(`/recommendations/similar/${id}`).catch(() => ({ products: [] })),
        ]);

        if (productRes) {
          setProduct(mapProduct(productRes));
        }

        const similar = (similarRes.products || similarRes.similar || []).map(mapProduct);
        setSimilarProducts(similar);
      } catch (error) {
        console.error('Failed to load product:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchProduct();
    setActiveImage(0);
    setQuantity(1);
    setActiveTab('description');
    setReviewPage(1);
    setReviewSort('newest');
  }, [id, fetchReviews]);

  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };

  const handleHelpful = async (reviewId) => {
    if (votedReviews.includes(reviewId)) return;
    try {
      await api(`/reviews/${reviewId}/helpful`, { method: 'POST' });
      setReviews(prev => prev.map(r => r.id === reviewId ? { ...r, helpfulCount: r.helpfulCount + 1 } : r));
      const updated = [...votedReviews, reviewId];
      setVotedReviews(updated);
      localStorage.setItem('votedReviews', JSON.stringify(updated));
    } catch (err) {
      console.error('Failed to mark helpful:', err);
    }
  };

  const handleDeleteReview = async (reviewId) => {
    if (!window.confirm(t('review.deleteConfirm'))) return;
    try {
      await api(`/reviews/${reviewId}?user_id=${encodeURIComponent(user.id)}`, { method: 'DELETE' });
      await fetchReviews(1, reviewSort);
      setReviewPage(1);
    } catch (err) {
      alert(err.message || 'Failed to delete review');
    }
  };

  const handleSortChange = (newSort) => {
    setReviewSort(newSort);
    setReviewPage(1);
    fetchReviews(1, newSort);
  };

  const handleLoadMore = () => {
    const nextPage = reviewPage + 1;
    setReviewPage(nextPage);
    fetchReviews(nextPage, reviewSort, true);
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

  // Build image gallery from product data
  const galleryImages = product
    ? (product.images?.length > 0
        ? product.images
        : [product.imageUrl || `https://picsum.photos/seed/${product.id}/600/600`])
    : [];

  // Urgency countdown (demo)
  const urgencyHours = 14;
  const urgencyMinutes = 32;

  // Delivery date (3 days from now, Korean locale)
  const deliveryDate = new Date(Date.now() + 3 * 86400000).toLocaleDateString('ko-KR', {
    month: 'long',
    day: 'numeric',
    weekday: 'long',
  });

  // Review rating distribution (from loaded reviews; distribution bars only shown when all loaded)
  const allReviewsLoaded = !reviewHasMore && reviews.length > 0;
  const ratingDist = [5, 4, 3, 2, 1].map(star => ({
    star,
    count: reviews.filter(r => Math.round(r.rating) === star).length,
    pct: allReviewsLoaded && reviews.length > 0 ? Math.round((reviews.filter(r => Math.round(r.rating) === star).length / reviews.length) * 100) : 0,
  }));
  // Use product-level rating (aggregated across all reviews) instead of loaded subset
  const avgRating = (product?.rating || 0).toFixed(1);

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

  const stockAvailable = product.stock?.available || 0;
  const isLowStock = stockAvailable > 0 && stockAvailable <= 10;
  const isOutOfStock = stockAvailable === 0 && product.status !== 'active';

  return (
    <div className="max-w-7xl mx-auto px-4 py-6">
      {/* ============ Breadcrumb ============ */}
      <nav className="flex items-center gap-1.5 text-sm text-secondary mb-6">
        <Link to="/" className="hover:text-brand-500 transition-colors">Home</Link>
        <span className="material-symbols-outlined text-[14px] text-outline-variant">chevron_right</span>
        <Link to="/products" className="hover:text-brand-500 transition-colors">
          {product.categoryName || 'Products'}
        </Link>
        <span className="material-symbols-outlined text-[14px] text-outline-variant">chevron_right</span>
        <span className="text-on-surface font-medium truncate max-w-[250px]">{product.name}</span>
      </nav>

      {/* ============ Main Product Grid ============ */}
      <div className="grid grid-cols-12 gap-6 mb-12">

        {/* ---- Image Gallery (6 col) ---- */}
        <div className="col-span-12 md:col-span-6">
          <div className="flex gap-3">
            {/* Thumbnails */}
            <div className="hidden md:flex flex-col gap-2 flex-shrink-0">
              {galleryImages.map((src, i) => (
                <button
                  key={i}
                  onClick={() => setActiveImage(i)}
                  onMouseEnter={() => setActiveImage(i)}
                  className={`w-16 h-16 rounded-lg overflow-hidden border-2 transition-all ${
                    i === activeImage ? 'border-brand-500 shadow-md' : 'border-outline-variant/30 hover:border-outline-variant'
                  }`}
                >
                  <img src={src} alt="" className="w-full h-full object-cover" loading="lazy" />
                </button>
              ))}
            </div>

            {/* Main image */}
            <div
              className="relative flex-1 aspect-square bg-surface-container rounded-xl overflow-hidden cursor-zoom-in group"
              onClick={() => setImageZoom(!imageZoom)}
            >
              <img
                src={galleryImages[activeImage]}
                alt={product.name}
                className={`w-full h-full object-contain transition-transform duration-300 ${imageZoom ? 'scale-150' : 'group-hover:scale-105'}`}
              />
              {product.discount > 0 && (
                <span className="absolute top-3 left-3 bg-red-600 text-white text-xs font-bold px-2.5 py-1 rounded-full">
                  -{product.discount}%
                </span>
              )}
              <button className="absolute top-3 right-3 w-9 h-9 bg-white/80 backdrop-blur rounded-full flex items-center justify-center hover:bg-white transition-colors shadow-sm">
                <span className="material-symbols-outlined text-[20px] text-on-surface-variant">zoom_in</span>
              </button>
            </div>
          </div>

          {/* Mobile thumbnails */}
          <div className="flex md:hidden gap-2 mt-3 overflow-x-auto pb-1">
            {galleryImages.map((src, i) => (
              <button
                key={i}
                onClick={() => setActiveImage(i)}
                className={`w-14 h-14 flex-shrink-0 rounded-lg overflow-hidden border-2 transition-all ${
                  i === activeImage ? 'border-brand-500' : 'border-outline-variant/30'
                }`}
              >
                <img src={src} alt="" className="w-full h-full object-cover" />
              </button>
            ))}
          </div>
        </div>

        {/* ---- Product Info (3 col) ---- */}
        <div className="col-span-12 md:col-span-3">
          {/* Brand */}
          {product.brand && (
            <Link to={`/products?query=${encodeURIComponent(product.brand)}`} className="text-sm text-brand-500 hover:text-brand-700 hover:underline font-medium">
              {product.brand}
            </Link>
          )}

          {/* Name */}
          <h1 className="text-xl font-bold text-on-surface font-[family-name:var(--font-headline)] mb-2 mt-1 leading-tight">
            {product.name}
          </h1>

          {/* Rating */}
          <div className="flex items-center gap-2 mb-4">
            <StarRating rating={product.rating} />
            <span className="text-sm text-brand-500 hover:text-brand-700 cursor-pointer">
              {product.reviewCount || reviews.length || 0} ratings
            </span>
          </div>

          <hr className="border-outline-variant/30 mb-4" />

          {/* Price block */}
          <div className="mb-4">
            {product.discount > 0 && (
              <div className="flex items-center gap-2 mb-1">
                <span className="text-sm text-red-600 font-bold">-{product.discount}%</span>
                <span className="text-sm text-secondary line-through">{formatPrice(product.originalPrice)}</span>
              </div>
            )}
            <p className="text-2xl font-bold text-on-surface font-[family-name:var(--font-headline)]">
              {formatPrice(product.price)}
            </p>
          </div>

          <hr className="border-outline-variant/30 mb-4" />

          {/* Specs table */}
          <table className="w-full text-sm mb-5">
            <tbody>
              {product.brand && (
                <tr className="border-b border-outline-variant/20">
                  <td className="py-2 pr-4 font-semibold text-on-surface whitespace-nowrap">{t('detail.brand')}</td>
                  <td className="py-2 text-on-surface-variant">{product.brand}</td>
                </tr>
              )}
              {product.attributes?.weight && (
                <tr className="border-b border-outline-variant/20">
                  <td className="py-2 pr-4 font-semibold text-on-surface whitespace-nowrap">{t('detail.weight')}</td>
                  <td className="py-2 text-on-surface-variant">{product.attributes.weight}</td>
                </tr>
              )}
              {product.attributes?.origin && (
                <tr className="border-b border-outline-variant/20">
                  <td className="py-2 pr-4 font-semibold text-on-surface whitespace-nowrap">{t('detail.origin')}</td>
                  <td className="py-2 text-on-surface-variant">{product.attributes.origin}</td>
                </tr>
              )}
              {Object.entries(product.attributes || {})
                .filter(([k]) => !['weight', 'origin'].includes(k))
                .map(([key, value]) => (
                  <tr key={key} className="border-b border-outline-variant/20">
                    <td className="py-2 pr-4 font-semibold text-on-surface whitespace-nowrap capitalize">{key}</td>
                    <td className="py-2 text-on-surface-variant">{value}</td>
                  </tr>
                ))}
            </tbody>
          </table>

          {/* Tags */}
          {product.tags?.length > 0 && (
            <div className="flex flex-wrap gap-1.5 mb-4">
              {product.tags.map(tag => (
                <Link
                  key={tag}
                  to={`/products?query=${encodeURIComponent(tag)}`}
                  className="text-xs bg-surface-container-high text-on-surface-variant px-2.5 py-1 rounded-full hover:bg-brand-100 hover:text-brand-700 transition-colors"
                >
                  #{tag}
                </Link>
              ))}
            </div>
          )}

          {/* Short description */}
          {product.description && (
            <p className="text-sm text-on-surface-variant leading-relaxed line-clamp-4">
              {product.description}
            </p>
          )}
        </div>

        {/* ---- Buy Box (3 col) ---- */}
        <div className="col-span-12 md:col-span-3">
          <div className="border border-outline-variant/30 rounded-xl p-5 sticky top-24 bg-white">
            {/* Price */}
            <p className="text-3xl font-bold text-on-surface mb-1 font-[family-name:var(--font-headline)]">
              {formatPrice(product.price)}
            </p>

            {/* Urgency */}
            <p className="text-sm text-red-600 font-semibold mb-3">
              <span className="material-symbols-outlined text-[14px] align-middle mr-0.5">timer</span>
              {t('detail.endsIn', { h: urgencyHours, m: urgencyMinutes })}
            </p>

            {/* Free returns */}
            <p className="text-sm text-on-surface-variant mb-1">
              <span className="text-brand-500 font-semibold">{t('detail.freeReturns')}</span>
            </p>

            {/* Delivery */}
            <p className="text-sm text-on-surface-variant mb-4">
              {t('detail.freeDelivery')}{' '}
              <span className="font-bold text-on-surface">{deliveryDate}</span>
            </p>

            {/* Stock status */}
            {isOutOfStock ? (
              <p className="text-sm font-bold text-red-600 mb-4">{t('detail.outOfStock')}</p>
            ) : isLowStock ? (
              <p className="text-sm font-bold text-orange-600 mb-4">
                {t('detail.stockLeft', { count: stockAvailable })}
              </p>
            ) : (
              <p className="text-sm font-bold text-green-700 mb-4">{t('detail.inStock')}</p>
            )}

            {/* Quantity selector */}
            <div className="flex items-center gap-2 mb-4">
              <label className="text-sm text-on-surface font-medium">{t('common.qty')}</label>
              <div className="flex items-center border border-outline-variant rounded-lg overflow-hidden">
                <button
                  onClick={() => setQuantity(q => Math.max(1, q - 1))}
                  className="px-3 py-1.5 text-sm hover:bg-surface-low transition-colors"
                >
                  -
                </button>
                <span className="px-4 py-1.5 text-sm font-medium border-x border-outline-variant bg-surface-low min-w-[40px] text-center">
                  {quantity}
                </span>
                <button
                  onClick={() => setQuantity(q => Math.min(10, q + 1))}
                  className="px-3 py-1.5 text-sm hover:bg-surface-low transition-colors"
                >
                  +
                </button>
              </div>
            </div>

            {/* Add to Cart */}
            <button
              onClick={handleAddToCart}
              disabled={isOutOfStock}
              className="w-full bg-brand-500 hover:bg-brand-600 disabled:bg-gray-300 disabled:cursor-not-allowed text-white py-2.5 rounded-full font-bold text-sm transition-colors mb-2 shadow-sm"
            >
              {t('detail.addToCart')}
            </button>

            {/* Buy Now */}
            <Link
              to="/checkout"
              className="block w-full text-center bg-brand-300 hover:bg-brand-200 text-brand-900 py-2.5 rounded-full font-bold text-sm transition-colors mb-4 shadow-sm"
            >
              {t('detail.buyNow')}
            </Link>

            {/* Meta info */}
            <div className="space-y-2 text-xs text-secondary border-t border-outline-variant/30 pt-3">
              <div className="flex items-center gap-2">
                <span className="material-symbols-outlined text-[14px]">lock</span>
                {t('detail.secureTransaction')}
              </div>
              <div className="flex items-center gap-2">
                <span className="material-symbols-outlined text-[14px]">local_shipping</span>
                {t('detail.shipsFrom')}
              </div>
              <div className="flex items-center gap-2">
                <span className="material-symbols-outlined text-[14px]">storefront</span>
                {t('detail.soldBy')}
              </div>
            </div>

            {/* Add to Wishlist */}
            <button
              onClick={handleAddToWishlist}
              className="mt-4 w-full py-2 text-sm font-semibold text-on-surface border border-outline-variant/50 rounded-lg hover:bg-surface-low transition-colors flex items-center justify-center gap-1.5"
            >
              <span className="material-symbols-outlined text-[18px]">favorite</span>
              {t('detail.addToWishlist')}
            </button>
          </div>
        </div>
      </div>

      {/* ============ Tabbed Content Section ============ */}
      <div className="mb-16">
        <div className="border-b border-outline-variant/30 mb-6">
          <div className="flex gap-0">
            {['description', 'specs', 'reviews'].map(tab => (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                className={`px-6 py-3 text-sm font-semibold transition-colors relative ${
                  activeTab === tab
                    ? 'text-brand-500'
                    : 'text-secondary hover:text-on-surface'
                }`}
              >
                {t(`detail.${tab === 'reviews' ? 'reviews' : tab}`)}
                {tab === 'reviews' && reviewTotal > 0 && (
                  <span className="ml-1.5 text-xs bg-brand-100 text-brand-700 px-1.5 py-0.5 rounded-full">
                    {reviewTotal}
                  </span>
                )}
                {activeTab === tab && (
                  <span className="absolute bottom-0 left-0 right-0 h-0.5 bg-brand-500 rounded-full" />
                )}
              </button>
            ))}
          </div>
        </div>

        {/* Description Tab */}
        {activeTab === 'description' && (
          <div className="max-w-4xl">
            <div className="prose prose-sm max-w-none text-on-surface-variant leading-relaxed">
              <p className="text-base leading-7 whitespace-pre-wrap">{product.description}</p>
            </div>

            {/* Feature highlights from description */}
            {product.description && (
              <div className="mt-8 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                {[
                  { icon: 'verified', label: (product.brand ? `${product.brand} ` : '') + '정품 보증' },
                  { icon: 'local_shipping', label: '무료 배송' },
                  { icon: 'replay', label: '30일 무료 반품' },
                  { icon: 'support_agent', label: '24/7 고객 지원' },
                ].map(({ icon, label }) => (
                  <div key={icon} className="flex items-center gap-3 p-4 bg-surface-container rounded-xl">
                    <span className="material-symbols-outlined text-brand-500 text-[24px]" style={{ fontVariationSettings: "'FILL' 1" }}>{icon}</span>
                    <span className="text-sm font-medium text-on-surface">{label}</span>
                  </div>
                ))}
              </div>
            )}

            {/* Product images gallery */}
            {galleryImages.length > 1 && (
              <div className="mt-8">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  {galleryImages.map((src, i) => (
                    <div key={i} className="rounded-xl overflow-hidden bg-surface-container">
                      <img src={src} alt={`${product.name} - ${i + 1}`} className="w-full h-auto object-contain" loading="lazy" />
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* Specs Tab */}
        {activeTab === 'specs' && (
          <div className="max-w-2xl">
            <table className="w-full text-sm">
              <tbody>
                {[
                  [t('detail.brand'), product.brand],
                  ['Category', product.categoryName],
                  [t('detail.weight'), product.attributes?.weight],
                  [t('detail.origin'), product.attributes?.origin],
                  ...Object.entries(product.attributes || {})
                    .filter(([k]) => !['weight', 'origin'].includes(k))
                    .map(([k, v]) => [k === 'crawled_specs' ? '상세 사양' : k, v]),
                  ['Product ID', product.id],
                  ['Status', product.status],
                ].filter(([, v]) => v).map(([label, value], i) => (
                  <tr key={i} className={i % 2 === 0 ? 'bg-surface-container' : ''}>
                    <td className="py-3 px-4 font-semibold text-on-surface whitespace-nowrap w-1/3">{label}</td>
                    <td className="py-3 px-4 text-on-surface-variant">{value}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Reviews Tab */}
        {activeTab === 'reviews' && (
          <div>
            {/* Review header: write button + sort */}
            <div className="flex items-center justify-between mb-6">
              <div className="flex items-center gap-3">
                {user ? (
                  <button
                    onClick={() => { setEditingReview(null); setShowReviewForm(true); }}
                    className="px-5 py-2 text-sm font-bold text-white bg-brand-500 rounded-full hover:bg-brand-600 transition-colors flex items-center gap-1.5"
                  >
                    <span className="material-symbols-outlined text-[18px]">rate_review</span>
                    {t('review.writeReview')}
                  </button>
                ) : (
                  <Link to="/login" className="text-sm text-brand-500 hover:underline">{t('review.loginRequired')}</Link>
                )}
              </div>
              {reviews.length > 0 && (
                <div className="flex items-center gap-2">
                  <span className="text-xs text-secondary">{t('review.sortBy')}:</span>
                  <select
                    value={reviewSort}
                    onChange={(e) => handleSortChange(e.target.value)}
                    className="text-sm border border-outline-variant/50 rounded-lg px-2 py-1.5 bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
                  >
                    {['newest', 'oldest', 'highest', 'lowest', 'mostHelpful'].map(opt => (
                      <option key={opt} value={opt === 'mostHelpful' ? 'helpful' : opt}>{t(`review.${opt}`)}</option>
                    ))}
                  </select>
                </div>
              )}
            </div>

            {reviews.length === 0 ? (
              <p className="text-secondary py-8 text-center">{t('detail.noReviews')}</p>
            ) : (
              <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
                {/* Rating summary sidebar */}
                <div className="lg:col-span-4">
                  <div className="bg-surface-container rounded-xl p-6 sticky top-24">
                    <div className="text-center mb-4">
                      <p className="text-5xl font-bold text-on-surface font-[family-name:var(--font-headline)]">{avgRating}</p>
                      <div className="flex justify-center mt-1"><StarRating rating={parseFloat(avgRating)} size={22} /></div>
                      <p className="text-sm text-secondary mt-1">{t('detail.basedOnReviews', { count: reviewTotal || reviews.length })}</p>
                    </div>

                    <hr className="border-outline-variant/30 my-4" />

                    {/* Rating distribution bars (only accurate when all reviews loaded) */}
                    {allReviewsLoaded && (
                    <div className="space-y-2">
                      {ratingDist.map(({ star, count, pct }) => (
                        <div key={star} className="flex items-center gap-2">
                          <span className="text-sm text-on-surface-variant w-8">{star}
                            <span className="material-symbols-outlined text-[12px] text-brand-500 align-middle ml-0.5" style={{ fontVariationSettings: "'FILL' 1" }}>star</span>
                          </span>
                          <div className="flex-1 h-2 bg-outline-variant/20 rounded-full overflow-hidden">
                            <div
                              className="h-full bg-brand-500 rounded-full transition-all duration-500"
                              style={{ width: `${pct}%` }}
                            />
                          </div>
                          <span className="text-xs text-secondary w-10 text-right">{count} ({pct}%)</span>
                        </div>
                      ))}
                    </div>
                    )}
                  </div>
                </div>

                {/* Review list */}
                <div className="lg:col-span-8 space-y-4">
                  {reviews.map((review) => (
                    <div key={review.id} className="bg-white rounded-xl border border-outline-variant/20 p-5 shadow-sm hover:shadow-md transition-shadow">
                      <div className="flex items-start justify-between mb-3">
                        <div className="flex items-center gap-3">
                          <div className="w-10 h-10 bg-brand-100 rounded-full flex items-center justify-center flex-shrink-0">
                            <span className="text-sm font-bold text-brand-700">
                              {(review.userName || 'A').charAt(0).toUpperCase()}
                            </span>
                          </div>
                          <div>
                            <p className="font-bold text-on-surface text-sm">{review.userName || 'Anonymous'}</p>
                            {review.verifiedPurchase && (
                              <p className="text-xs text-green-700 flex items-center gap-0.5">
                                <span className="material-symbols-outlined text-[12px]" style={{ fontVariationSettings: "'FILL' 1" }}>check_circle</span>
                                {t('detail.verifiedPurchase')}
                              </p>
                            )}
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <span className="text-xs text-secondary">
                            {review.createdAt && new Date(review.createdAt).toLocaleDateString('ko-KR')}
                          </span>
                          {/* Edit/Delete menu for own reviews */}
                          {user?.id && review.userId === user.id && (
                            <div className="relative">
                              <button
                                onClick={() => setReviewMenuOpen(reviewMenuOpen === review.id ? null : review.id)}
                                className="text-secondary hover:text-on-surface transition-colors p-1 rounded-full hover:bg-surface-container"
                              >
                                <span className="material-symbols-outlined text-[18px]">more_vert</span>
                              </button>
                              {reviewMenuOpen === review.id && (
                                <div className="absolute right-0 top-8 bg-white rounded-lg shadow-lg border border-outline-variant/20 py-1 z-10 min-w-[120px]">
                                  <button
                                    onClick={() => { setEditingReview(review); setShowReviewForm(true); setReviewMenuOpen(null); }}
                                    className="w-full px-4 py-2 text-left text-sm text-on-surface hover:bg-surface-container flex items-center gap-2"
                                  >
                                    <span className="material-symbols-outlined text-[16px]">edit</span>
                                    {t('review.edit')}
                                  </button>
                                  <button
                                    onClick={() => { handleDeleteReview(review.id); setReviewMenuOpen(null); }}
                                    className="w-full px-4 py-2 text-left text-sm text-red-600 hover:bg-red-50 flex items-center gap-2"
                                  >
                                    <span className="material-symbols-outlined text-[16px]">delete</span>
                                    {t('review.delete')}
                                  </button>
                                </div>
                              )}
                            </div>
                          )}
                        </div>
                      </div>

                      {/* Stars + Title */}
                      <div className="flex items-center gap-2 mb-2">
                        <StarRating rating={review.rating} size={16} />
                        {review.title && <span className="text-sm font-bold text-on-surface">{review.title}</span>}
                      </div>

                      {/* Body */}
                      <p className="text-sm text-on-surface-variant leading-relaxed mb-3">{review.content}</p>

                      {/* Review images */}
                      {review.images?.length > 0 && (
                        <div className="flex gap-2 mb-3">
                          {review.images.map((img, i) => (
                            <div key={i} className="w-20 h-20 rounded-lg overflow-hidden bg-surface-container">
                              <img src={img} alt="" className="w-full h-full object-cover" loading="lazy" />
                            </div>
                          ))}
                        </div>
                      )}

                      {/* Helpful button */}
                      <button
                        onClick={() => handleHelpful(review.id)}
                        disabled={votedReviews.includes(review.id)}
                        className={`text-xs flex items-center gap-1 px-2 py-1 rounded-full transition-colors ${
                          votedReviews.includes(review.id)
                            ? 'text-brand-500 bg-brand-50'
                            : 'text-secondary hover:text-brand-500 hover:bg-brand-50'
                        }`}
                      >
                        <span className="material-symbols-outlined text-[14px]" style={{ fontVariationSettings: votedReviews.includes(review.id) ? "'FILL' 1" : "'FILL' 0" }}>thumb_up</span>
                        {review.helpfulCount > 0 ? t('review.helpfulCount', { count: review.helpfulCount }) : t('review.helpful')}
                      </button>
                    </div>
                  ))}

                  {/* Load More */}
                  {reviewHasMore && (
                    <div className="text-center pt-4">
                      <button
                        onClick={handleLoadMore}
                        className="px-6 py-2.5 text-sm font-semibold text-brand-500 border border-brand-500 rounded-full hover:bg-brand-50 transition-colors"
                      >
                        {t('review.loadMore')}
                      </button>
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* Review Form Modal */}
            {showReviewForm && (
              <ReviewForm
                productId={id}
                initialData={editingReview}
                onClose={() => { setShowReviewForm(false); setEditingReview(null); }}
                onSuccess={() => { fetchReviews(1, reviewSort); setReviewPage(1); }}
              />
            )}
          </div>
        )}
      </div>

      {/* ============ Frequently Bought Together ============ */}
      {similarProducts.length >= 2 && (
        <section className="mb-16">
          <h2 className="text-xl font-bold text-on-surface font-[family-name:var(--font-headline)] mb-6">
            {t('detail.boughtTogether')}
          </h2>
          <div className="flex items-center gap-3 flex-wrap">
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
                    loading="lazy"
                  />
                </Link>
              </div>
            ))}

            <div className="ml-6">
              <p className="text-sm text-secondary mb-1">{t('detail.totalPrice')}:</p>
              <p className="text-2xl font-bold text-on-surface font-[family-name:var(--font-headline)] mb-3">
                {formatPrice(
                  (product.price || 0) +
                  (similarProducts[0]?.price || 0) +
                  (similarProducts[1]?.price || 0)
                )}
              </p>
              <button className="bg-brand-500 hover:bg-brand-600 text-white px-6 py-2 rounded-full text-sm font-bold transition-colors shadow-sm">
                {t('detail.addAllToCart')}
              </button>
            </div>
          </div>
        </section>
      )}

      {/* ============ Similar Products ============ */}
      {similarProducts.length > 0 && (
        <section className="mb-16">
          <h2 className="text-xl font-bold text-on-surface font-[family-name:var(--font-headline)] mb-6">
            {t('detail.similar')}
          </h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
            {similarProducts.slice(0, 5).map((p) => (
              <Link
                key={p.id}
                to={`/products/${p.id}`}
                className="bg-white rounded-xl overflow-hidden border border-outline-variant/20 hover:shadow-lg transition-all group block"
              >
                <div className="aspect-square bg-surface-container overflow-hidden relative">
                  <img
                    src={p.imageUrl || `https://picsum.photos/seed/${p.id}/400/400`}
                    alt={p.name}
                    className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                    loading="lazy"
                  />
                  {p.discount > 0 && (
                    <span className="absolute top-2 left-2 bg-red-600 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full">
                      -{p.discount}%
                    </span>
                  )}
                </div>
                <div className="p-3">
                  <h3 className="font-bold text-on-surface text-xs truncate mb-1 font-[family-name:var(--font-headline)]">
                    {p.name}
                  </h3>
                  <div className="flex items-center gap-1 mb-1">
                    <StarRating rating={p.rating || 4} size={12} />
                    <span className="text-[10px] text-secondary">({p.reviewCount || 0})</span>
                  </div>
                  <p className="font-bold text-brand-900 text-sm font-[family-name:var(--font-headline)]">
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
