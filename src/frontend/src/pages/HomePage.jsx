import { useState, useEffect, useRef } from 'react';
import { Link } from 'react-router-dom';
import ProductCard from '../components/ProductCard';
import { api, mapProduct } from '../api';
import { useI18n } from '../context/I18nContext';

export default function HomePage() {
  const { t } = useI18n();
  const [featuredProducts, setFeaturedProducts] = useState([]);
  const [trendingProducts, setTrendingProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [heroSlide, setHeroSlide] = useState(0);
  const trendingScrollRef = useRef(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [productsRes, trendingRes] = await Promise.all([
          api('/products?limit=8'),
          api('/recommendations/trending').catch(() => ({ products: [] })),
        ]);
        setFeaturedProducts((productsRes.products || productsRes || []).map(mapProduct));
        const trending = (trendingRes.products || trendingRes || []).map(p => {
          if (p.product_id && !p.id && !p._id) p.id = p.product_id;
          return mapProduct(p);
        });
        setTrendingProducts(trending);
      } catch (error) {
        console.error('Failed to load data:', error);
      } finally {
        setLoading(false);
      }
    };
    fetchData();
  }, []);

  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };

  const scrollTrending = (dir) => {
    if (!trendingScrollRef.current) return;
    const amount = 320;
    trendingScrollRef.current.scrollBy({ left: dir === 'left' ? -amount : amount, behavior: 'smooth' });
  };

  // Use first 3 products for "The Architectural Series" section
  const archProducts = featuredProducts.slice(0, 3);

  return (
    <div>
      {/* ============ Hero Section ============ */}
      <section className="relative w-full h-[600px] overflow-hidden">
        {/* Background image */}
        <img
          src="https://picsum.photos/seed/vellure-hero/1920/600"
          alt="Hero"
          className="absolute inset-0 w-full h-full object-cover"
        />
        {/* Gradient overlay */}
        <div className="absolute inset-0 bg-gradient-to-r from-brand-900/80 via-brand-900/50 to-transparent" />

        {/* Hero content */}
        <div className="relative z-10 max-w-7xl mx-auto px-6 h-full flex flex-col justify-center">
          <p className="text-brand-400 font-[family-name:var(--font-headline)] font-bold text-sm tracking-[0.2em] uppercase mb-3">
            {t('home.subtitle')}
          </p>
          <h1 className="text-4xl md:text-6xl font-extrabold text-white leading-tight max-w-xl font-[family-name:var(--font-headline)] mb-2">
            The Autumn{' '}
            <span className="text-brand-400">Curation</span>
          </h1>
          <p className="text-white/70 text-base md:text-lg max-w-md mb-8 leading-relaxed">
            {t('home.topPickDesc')}
          </p>

          {/* CTA buttons */}
          <div className="flex items-center gap-4">
            <Link
              to="/products"
              className="bg-brand-500 hover:bg-brand-600 text-white px-7 py-3 rounded-lg font-bold text-sm transition-colors shadow-lg"
            >
              {t('home.viewAll')}
            </Link>
            <Link
              to="/products"
              className="border border-white/40 text-white hover:bg-white/10 px-7 py-3 rounded-lg font-bold text-sm transition-colors"
            >
              {t('home.viewDetails')}
            </Link>
          </div>

          {/* Pagination dots */}
          <div className="flex items-center gap-2 mt-10">
            {[0, 1, 2].map(i => (
              <button
                key={i}
                onClick={() => setHeroSlide(i)}
                className={`w-2.5 h-2.5 rounded-full transition-all ${
                  i === heroSlide ? 'bg-brand-500 w-8' : 'bg-white/40'
                }`}
                aria-label={`Slide ${i + 1}`}
              />
            ))}
          </div>
        </div>
      </section>

      {/* ============ Bento Grid Categories ============ */}
      <section className="max-w-7xl mx-auto px-4 md:px-6 -mt-20 relative z-20 pb-12">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-5">
          {/* Card 1: Modern Bohemian Living (2-col) */}
          <div className="md:col-span-2 bg-white rounded-xl overflow-hidden shadow-lg hover:shadow-xl transition-shadow group">
            <div className="p-6 pb-4">
              <h3 className="text-lg font-bold text-brand-900 font-[family-name:var(--font-headline)] mb-1">
                Modern Bohemian Living
              </h3>
              <p className="text-sm text-secondary mb-4">Curated essentials for warm spaces</p>
            </div>
            <div className="grid grid-cols-2 gap-1 px-4 pb-4">
              {[1, 2, 3, 4].map(i => (
                <Link
                  key={i}
                  to="/products?category=home"
                  className="aspect-square bg-surface-container overflow-hidden rounded-lg"
                >
                  <img
                    src={`https://picsum.photos/seed/bento-boho-${i}/300/300`}
                    alt=""
                    className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                  />
                </Link>
              ))}
            </div>
          </div>

          {/* Card 2: Fall Trends (1-col, tall image) */}
          <div className="md:col-span-1 bg-white rounded-xl overflow-hidden shadow-lg hover:shadow-xl transition-shadow group">
            <Link to="/products?category=fashion" className="block h-full">
              <div className="relative h-full min-h-[320px]">
                <img
                  src="https://picsum.photos/seed/bento-fall/400/600"
                  alt="Fall Trends"
                  className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-brand-900/70 to-transparent" />
                <div className="absolute bottom-0 left-0 p-5">
                  <h3 className="text-lg font-bold text-white font-[family-name:var(--font-headline)] mb-2">
                    Fall Trends
                  </h3>
                  <span className="inline-flex items-center gap-1 text-sm font-bold text-brand-400 group-hover:text-brand-300 transition-colors">
                    Shop Now
                    <span className="material-symbols-outlined text-[16px]">arrow_forward</span>
                  </span>
                </div>
              </div>
            </Link>
          </div>

          {/* Card 3: Smart Workspace (1-col, 2x2 grid + badge) */}
          <div className="md:col-span-1 bg-white rounded-xl overflow-hidden shadow-lg hover:shadow-xl transition-shadow group">
            <div className="p-5 pb-3">
              <div className="inline-block bg-brand-500 text-white text-[10px] font-bold px-2 py-0.5 rounded-sm uppercase mb-2">
                20% Off Bundles
              </div>
              <h3 className="text-lg font-bold text-brand-900 font-[family-name:var(--font-headline)]">
                Smart Workspace
              </h3>
            </div>
            <div className="grid grid-cols-2 gap-1 px-4 pb-4">
              {[1, 2, 3, 4].map(i => (
                <Link
                  key={i}
                  to="/products?category=electronics"
                  className="aspect-square bg-surface-container overflow-hidden rounded-lg"
                >
                  <img
                    src={`https://picsum.photos/seed/bento-workspace-${i}/300/300`}
                    alt=""
                    className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                  />
                </Link>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* ============ The Architectural Series (3 product cards) ============ */}
      <section className="py-14 bg-white">
        <div className="max-w-7xl mx-auto px-4 md:px-6">
          <div className="flex items-end justify-between mb-8">
            <div>
              <p className="text-brand-500 font-[family-name:var(--font-headline)] font-bold text-xs tracking-[0.2em] uppercase mb-1">
                {t('home.subtitle')}
              </p>
              <h2 className="text-3xl font-extrabold text-brand-900 font-[family-name:var(--font-headline)]">
                {t('home.curatedCollection')}
              </h2>
            </div>
            <Link
              to="/products"
              className="text-brand-500 hover:text-brand-700 font-semibold text-sm flex items-center gap-1 transition-colors"
            >
              {t('home.viewAll')}
              <span className="material-symbols-outlined text-[16px]">arrow_forward</span>
            </Link>
          </div>

          {loading ? (
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              {[...Array(3)].map((_, i) => (
                <div key={i} className="animate-pulse">
                  <div className="aspect-[3/4] bg-surface-high rounded-xl mb-4" />
                  <div className="h-4 bg-surface-high rounded w-3/4 mb-2" />
                  <div className="h-4 bg-surface-high rounded w-1/2" />
                </div>
              ))}
            </div>
          ) : archProducts.length === 0 ? (
            <p className="text-secondary text-center py-8">{t('home.loading')}</p>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              {archProducts.map((product) => (
                <Link
                  key={product.id}
                  to={`/products/${product.id}`}
                  className="group block"
                >
                  <div className="aspect-[3/4] bg-surface-container rounded-xl overflow-hidden mb-4">
                    <img
                      src={product.imageUrl || `https://picsum.photos/seed/${product.id}/600/800`}
                      alt={product.name}
                      className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                    />
                  </div>
                  <h3 className="font-bold text-on-surface group-hover:text-brand-500 transition-colors font-[family-name:var(--font-headline)] mb-1">
                    {product.name}
                  </h3>
                  <p className="text-lg font-bold text-brand-900 font-[family-name:var(--font-headline)]">
                    {formatPrice(product.price)}
                  </p>
                </Link>
              ))}
            </div>
          )}
        </div>
      </section>

      {/* ============ VELLURE+ Membership Dark Card + Featured Products ============ */}
      <section className="py-14 bg-surface-low">
        <div className="max-w-7xl mx-auto px-4 md:px-6">
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
            {/* Product grid */}
            <div className="lg:col-span-8">
              <h2 className="text-2xl font-extrabold text-brand-900 font-[family-name:var(--font-headline)] mb-6">
                {t('home.trending')}
              </h2>
              {loading ? (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
                  {[...Array(4)].map((_, i) => (
                    <div key={i} className="bg-white rounded-xl overflow-hidden animate-pulse shadow-sm">
                      <div className="bg-surface-high h-48 w-full" />
                      <div className="p-4 space-y-3">
                        <div className="bg-surface-high h-4 rounded w-3/4" />
                        <div className="bg-surface-high h-4 rounded w-1/2" />
                      </div>
                    </div>
                  ))}
                </div>
              ) : featuredProducts.length === 0 ? (
                <p className="text-secondary text-center py-8">{t('home.loading')}</p>
              ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
                  {featuredProducts.slice(0, 4).map((product) => (
                    <ProductCard key={product.id} product={product} />
                  ))}
                </div>
              )}
            </div>

            {/* VELLURE+ Membership sidebar */}
            <div className="lg:col-span-4">
              <div className="bg-brand-900 rounded-xl p-8 text-white sticky top-24">
                <div className="flex items-center gap-2 mb-4">
                  <span className="material-symbols-outlined text-brand-400 text-3xl" style={{ fontVariationSettings: "'FILL' 1" }}>
                    workspace_premium
                  </span>
                  <span className="text-brand-400 font-bold text-lg font-[family-name:var(--font-headline)]">
                    VELLURE+
                  </span>
                </div>
                <h3 className="text-xl font-bold mb-3 font-[family-name:var(--font-headline)]">
                  {t('home.newMember')}
                </h3>
                <p className="text-stone-300 text-sm mb-6 leading-relaxed">
                  {t('home.newMemberDesc')}
                </p>
                <ul className="space-y-3 mb-8">
                  {[
                    { icon: 'local_shipping', text: t('home.badge.ship') },
                    { icon: 'verified', text: t('home.badge.auth') },
                    { icon: 'shield', text: t('home.badge.secure') },
                  ].map(({ icon, text }) => (
                    <li key={icon} className="flex items-center gap-3 text-sm text-stone-200">
                      <span className="material-symbols-outlined text-brand-400 text-[18px]" style={{ fontVariationSettings: "'FILL' 1" }}>
                        {icon}
                      </span>
                      {text}
                    </li>
                  ))}
                </ul>
                <Link
                  to="/register"
                  className="block w-full text-center bg-brand-500 hover:bg-brand-400 text-white px-6 py-3 rounded-lg font-bold text-sm transition-colors shadow-lg"
                >
                  {t('home.createAccount')}
                </Link>
                <div className="absolute -right-10 -bottom-10 w-48 h-48 bg-white/5 rounded-full blur-3xl" />
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ============ Recommended for You (horizontal scroll) ============ */}
      {trendingProducts.length > 0 && (
        <section className="py-14 bg-white">
          <div className="max-w-7xl mx-auto px-4 md:px-6">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-2xl font-extrabold text-brand-900 font-[family-name:var(--font-headline)]">
                {t('home.trending')}
              </h2>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => scrollTrending('left')}
                  className="w-9 h-9 rounded-full bg-surface-high hover:bg-surface-highest flex items-center justify-center transition-colors"
                  aria-label="Scroll left"
                >
                  <span className="material-symbols-outlined text-[18px] text-on-surface">chevron_left</span>
                </button>
                <button
                  onClick={() => scrollTrending('right')}
                  className="w-9 h-9 rounded-full bg-surface-high hover:bg-surface-highest flex items-center justify-center transition-colors"
                  aria-label="Scroll right"
                >
                  <span className="material-symbols-outlined text-[18px] text-on-surface">chevron_right</span>
                </button>
              </div>
            </div>
            <div
              ref={trendingScrollRef}
              className="flex gap-5 overflow-x-auto pb-4 scrollbar-hide snap-x snap-mandatory"
              style={{ scrollbarWidth: 'none', msOverflowStyle: 'none' }}
            >
              {trendingProducts.map((product) => (
                <div key={product.id} className="min-w-[260px] max-w-[260px] snap-start shrink-0">
                  <ProductCard product={product} />
                </div>
              ))}
            </div>
          </div>
        </section>
      )}

      {/* ============ Trust Badges ============ */}
      <section className="py-14 bg-surface-low">
        <div className="max-w-7xl mx-auto px-4 md:px-6">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
            {[
              { icon: 'verified', title: t('home.badge.auth'), desc: t('home.badge.authDesc') },
              { icon: 'rocket_launch', title: t('home.badge.ship'), desc: t('home.badge.shipDesc') },
              { icon: 'shield', title: t('home.badge.secure'), desc: t('home.badge.secureDesc') },
            ].map(({ icon, title, desc }) => (
              <div key={icon} className="bg-white rounded-xl p-6 text-center shadow-sm">
                <span
                  className="material-symbols-outlined text-brand-500 text-4xl mb-4 block"
                  style={{ fontVariationSettings: "'FILL' 1" }}
                >
                  {icon}
                </span>
                <h4 className="font-bold text-brand-900 mb-2 font-[family-name:var(--font-headline)]">{title}</h4>
                <p className="text-sm text-secondary leading-relaxed">{desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>
    </div>
  );
}
