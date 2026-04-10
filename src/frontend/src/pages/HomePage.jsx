import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import ProductCard from '../components/ProductCard';
import { api, mapProduct } from '../api';
import { useI18n } from '../context/I18nContext';

const CATEGORY_DEFS = [
  { id: 'electronics', key: 'cat.electronics', icon: 'devices', color: 'bg-blue-50 text-blue-700' },
  { id: 'fashion', key: 'cat.fashion', icon: 'checkroom', color: 'bg-pink-50 text-pink-700' },
  { id: 'home', key: 'cat.home', icon: 'chair', color: 'bg-green-50 text-green-700' },
  { id: 'beauty', key: 'cat.beauty', icon: 'spa', color: 'bg-purple-50 text-purple-700' },
  { id: 'sports', key: 'cat.sports', icon: 'fitness_center', color: 'bg-orange-50 text-orange-700' },
  { id: 'food', key: 'cat.food', icon: 'restaurant', color: 'bg-red-50 text-red-700' },
];

export default function HomePage() {
  const { t } = useI18n();
  const [featuredProducts, setFeaturedProducts] = useState([]);
  const [trendingProducts, setTrendingProducts] = useState([]);
  const [loading, setLoading] = useState(true);

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

  const topPick = featuredProducts[0];
  const dealPick = featuredProducts[1];

  const categories = CATEGORY_DEFS.map(c => ({ ...c, name: t(c.key) }));

  return (
    <div>
      {/* Hero / Bento Grid */}
      <section className="max-w-7xl mx-auto px-4 md:px-6 py-10 md:py-14">
        <header className="mb-10">
          <p className="text-brand-500 font-[family-name:var(--font-headline)] font-bold text-sm tracking-widest uppercase mb-2">{t('home.subtitle')}</p>
          <h1 className="text-4xl md:text-5xl font-extrabold text-brand-900 leading-tight max-w-2xl font-[family-name:var(--font-headline)]">
            {t('home.title')}
          </h1>
        </header>

        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
          {/* Main Feature Card */}
          {topPick && (
            <div className="lg:col-span-8 group">
              <Link to={`/products/${topPick.id}`} className="bg-white rounded-xl overflow-hidden shadow-[0_12px_32px_rgba(24,28,29,0.06)] flex flex-col md:flex-row h-full">
                <div className="md:w-1/2 overflow-hidden bg-surface-container">
                  <img
                    src={topPick.imageUrl || `https://picsum.photos/seed/${topPick.id}/600/600`}
                    alt={topPick.name}
                    className="w-full h-64 md:h-full object-cover group-hover:scale-105 transition-transform duration-700"
                  />
                </div>
                <div className="md:w-1/2 p-8 md:p-10 flex flex-col justify-center">
                  <div className="flex items-center gap-2 mb-4">
                    <span className="bg-brand-300 text-brand-900 text-[10px] font-bold px-2 py-0.5 rounded-full uppercase tracking-tight">{t('home.topPick')}</span>
                  </div>
                  <h3 className="text-2xl md:text-3xl font-bold text-brand-900 mb-3 leading-tight font-[family-name:var(--font-headline)]">{topPick.name}</h3>
                  <p className="text-on-surface-variant text-sm leading-relaxed mb-6">{topPick.description || t('home.topPickDesc')}</p>
                  <div className="mt-auto flex items-center justify-between">
                    <span className="text-2xl font-bold text-brand-900">{formatPrice(topPick.price)}</span>
                    <span className="bg-brand-500 hover:bg-brand-700 text-white px-5 py-2.5 rounded-md font-bold text-sm transition-all shadow-md flex items-center gap-2">
                      <span className="material-symbols-outlined text-[16px]">shopping_cart</span>
                      {t('home.viewDetails')}
                    </span>
                  </div>
                </div>
              </Link>
            </div>
          )}

          {/* Deal of the Day */}
          {dealPick && (
            <div className="lg:col-span-4 h-full">
              <Link to={`/products/${dealPick.id}`} className="bg-brand-900 text-white rounded-xl p-8 flex flex-col h-full shadow-lg relative overflow-hidden block">
                <div className="relative z-10">
                  <div className="bg-brand-500 text-white text-[10px] font-bold px-2 py-1 rounded-sm uppercase inline-block mb-6">{t('home.dealOfDay')}</div>
                  <h3 className="text-2xl font-bold mb-3 font-[family-name:var(--font-headline)]">{dealPick.name}</h3>
                  <p className="text-stone-300 text-sm mb-6 leading-relaxed">{dealPick.description || t('home.dealDesc')}</p>
                  <span className="text-3xl font-bold text-brand-400">{formatPrice(dealPick.price)}</span>
                </div>
                <div className="absolute -right-20 -bottom-20 w-64 h-64 bg-white/5 rounded-full blur-3xl" />
              </Link>
            </div>
          )}
        </div>
      </section>

      {/* Category Navigation */}
      <section className="bg-surface-low py-10">
        <div className="max-w-7xl mx-auto px-4 md:px-6">
          <div className="grid grid-cols-3 md:grid-cols-6 gap-4">
            {categories.map((category) => (
              <Link
                key={category.id}
                to={`/products?category=${category.id}`}
                className={`${category.color} rounded-xl p-5 text-center hover:shadow-md transition-all group`}
              >
                <span className="material-symbols-outlined text-3xl mb-2 block group-hover:scale-110 transition-transform">{category.icon}</span>
                <span className="text-sm font-medium">{category.name}</span>
              </Link>
            ))}
          </div>
        </div>
      </section>

      {/* Featured Products */}
      <section className="py-12">
        <div className="max-w-7xl mx-auto px-4 md:px-6">
          <div className="flex items-center justify-between mb-8">
            <h2 className="text-2xl font-extrabold text-brand-900 font-[family-name:var(--font-headline)]">{t('home.curatedCollection')}</h2>
            <Link to="/products" className="text-brand-500 hover:text-brand-700 font-semibold text-sm flex items-center gap-1 transition-colors">
              {t('home.viewAll')} <span className="material-symbols-outlined text-[16px]">arrow_forward</span>
            </Link>
          </div>
          {loading ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
              {[...Array(8)].map((_, i) => (
                <div key={i} className="bg-white rounded-xl overflow-hidden animate-pulse shadow-sm">
                  <div className="bg-surface-high h-48 w-full" />
                  <div className="p-4 space-y-3">
                    <div className="bg-surface-high h-4 rounded w-3/4" />
                    <div className="bg-surface-high h-4 rounded w-1/2" />
                    <div className="bg-surface-high h-6 rounded w-1/3" />
                  </div>
                </div>
              ))}
            </div>
          ) : featuredProducts.length === 0 ? (
            <p className="text-secondary text-center py-8">{t('home.loading')}</p>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
              {featuredProducts.map((product) => (
                <ProductCard key={product.id} product={product} />
              ))}
            </div>
          )}
        </div>
      </section>

      {/* Promotion Banner */}
      <section className="bg-brand-900 py-14">
        <div className="max-w-7xl mx-auto px-4 md:px-6 text-center text-white">
          <h2 className="text-3xl font-extrabold mb-4 font-[family-name:var(--font-headline)]">{t('home.newMember')}</h2>
          <p className="text-brand-300 text-lg mb-6">
            {t('home.newMemberDesc')}
          </p>
          <Link
            to="/register"
            className="inline-block bg-brand-500 hover:bg-brand-400 text-brand-900 px-8 py-3 rounded-md font-bold transition-all shadow-lg"
          >
            {t('home.createAccount')}
          </Link>
        </div>
      </section>

      {/* Trending Products */}
      {trendingProducts.length > 0 && (
        <section className="py-12 bg-surface-low">
          <div className="max-w-7xl mx-auto px-4 md:px-6">
            <div className="flex items-center justify-between mb-8">
              <h2 className="text-2xl font-extrabold text-brand-900 font-[family-name:var(--font-headline)]">{t('home.trending')}</h2>
              <Link to="/products" className="text-brand-500 hover:text-brand-700 font-semibold text-sm flex items-center gap-1 transition-colors">
                {t('home.viewAll')} <span className="material-symbols-outlined text-[16px]">arrow_forward</span>
              </Link>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
              {trendingProducts.map((product) => (
                <ProductCard key={product.id} product={product} />
              ))}
            </div>
          </div>
        </section>
      )}

      {/* Trust Badges */}
      <section className="py-14">
        <div className="max-w-7xl mx-auto px-4 md:px-6">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
            {[
              { icon: 'verified', title: t('home.badge.auth'), desc: t('home.badge.authDesc') },
              { icon: 'rocket_launch', title: t('home.badge.ship'), desc: t('home.badge.shipDesc') },
              { icon: 'shield', title: t('home.badge.secure'), desc: t('home.badge.secureDesc') },
            ].map(({ icon, title, desc }) => (
              <div key={icon} className="bg-surface-low rounded-xl p-6 text-center">
                <span className="material-symbols-outlined material-filled text-brand-500 text-4xl mb-4 block">{icon}</span>
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

function formatPrice(price) {
  if (price == null) return '';
  return `₩${Number(price).toLocaleString('ko-KR')}`;
}
