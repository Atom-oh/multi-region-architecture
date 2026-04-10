import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useCart } from '../context/CartContext';
import { useI18n } from '../context/I18nContext';

export default function Navbar() {
  const [searchQuery, setSearchQuery] = useState('');
  const { user, isLoggedIn, logout } = useAuth();
  const { cartCount } = useCart();
  const { t, lang, toggleLang } = useI18n();
  const navigate = useNavigate();

  const handleSearch = (e) => {
    e.preventDefault();
    if (searchQuery.trim()) {
      navigate(`/products?q=${encodeURIComponent(searchQuery.trim())}`);
    }
  };

  return (
    <nav className="bg-brand-900 text-white sticky top-0 z-50 shadow-lg">
      <div className="max-w-7xl mx-auto px-4 md:px-6">
        <div className="flex items-center justify-between h-14">
          <div className="flex items-center gap-8">
            <Link to="/" className="text-xl font-extrabold tracking-tighter text-white font-[family-name:var(--font-headline)] hover:opacity-90 transition-opacity">
              VELLURE
            </Link>
            <div className="hidden md:flex items-center gap-6 text-sm font-medium">
              <Link to="/products" className="text-stone-300 hover:text-white transition-colors">{t('nav.explore')}</Link>
              <Link to="/products?category=electronics" className="text-stone-300 hover:text-white transition-colors">{t('nav.deals')}</Link>
              <Link to="/orders" className="text-stone-300 hover:text-white transition-colors">{t('nav.orders')}</Link>
            </div>
          </div>

          <form onSubmit={handleSearch} className="hidden sm:block">
            <div className="relative">
              <span className="material-symbols-outlined absolute left-3 top-1/2 -translate-y-1/2 text-stone-400 text-[18px]">search</span>
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder={t('nav.search')}
                className="bg-white/10 border-none rounded-full py-1.5 pl-10 pr-4 text-sm text-white placeholder-stone-400 focus:outline-none focus:ring-1 focus:ring-brand-500 w-64"
              />
            </div>
          </form>

          <div className="flex items-center gap-2">
            <button
              onClick={toggleLang}
              className="text-stone-300 hover:bg-white/10 px-2.5 py-1 rounded-full transition-all text-xs font-bold border border-white/20"
            >
              {lang === 'ko' ? 'EN' : 'KO'}
            </button>

            <Link to="/cart" className="relative text-stone-300 hover:bg-white/10 p-2 rounded-full transition-all">
              <span className="material-symbols-outlined">shopping_cart</span>
              {cartCount > 0 && (
                <span className="absolute top-0 right-0 bg-brand-500 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full border-2 border-brand-900">
                  {cartCount}
                </span>
              )}
            </Link>

            {isLoggedIn ? (
              <div className="relative group">
                <button className="flex items-center gap-2 text-stone-300 hover:bg-white/10 p-2 rounded-full transition-all">
                  <span className="material-symbols-outlined">account_circle</span>
                  <span className="hidden md:inline text-sm">{user?.name}</span>
                </button>
                <div className="absolute right-0 mt-1 w-52 bg-white rounded-lg shadow-xl py-2 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all duration-200 border border-outline-variant/20">
                  <Link to="/profile" className="flex items-center gap-3 px-4 py-2.5 text-on-surface hover:bg-surface-low transition-colors text-sm">
                    <span className="material-symbols-outlined text-[18px]">person</span> {t('menu.profile')}
                  </Link>
                  <Link to="/wishlist" className="flex items-center gap-3 px-4 py-2.5 text-on-surface hover:bg-surface-low transition-colors text-sm">
                    <span className="material-symbols-outlined text-[18px]">favorite</span> {t('menu.wishlist')}
                  </Link>
                  <Link to="/notifications" className="flex items-center gap-3 px-4 py-2.5 text-on-surface hover:bg-surface-low transition-colors text-sm">
                    <span className="material-symbols-outlined text-[18px]">notifications</span> {t('menu.notifications')}
                  </Link>
                  <Link to="/seller" className="flex items-center gap-3 px-4 py-2.5 text-on-surface hover:bg-surface-low transition-colors text-sm">
                    <span className="material-symbols-outlined text-[18px]">storefront</span> {t('menu.seller')}
                  </Link>
                  <Link to="/returns" className="flex items-center gap-3 px-4 py-2.5 text-on-surface hover:bg-surface-low transition-colors text-sm">
                    <span className="material-symbols-outlined text-[18px]">assignment_return</span> {t('menu.returns')}
                  </Link>
                  <hr className="my-1 border-outline-variant/20" />
                  <button onClick={logout} className="flex items-center gap-3 px-4 py-2.5 text-red-600 hover:bg-red-50 transition-colors text-sm w-full text-left">
                    <span className="material-symbols-outlined text-[18px]">logout</span> {t('menu.logout')}
                  </button>
                </div>
              </div>
            ) : (
              <Link to="/login" className="text-stone-300 hover:bg-white/10 p-2 rounded-full transition-all">
                <span className="material-symbols-outlined">account_circle</span>
              </Link>
            )}
          </div>
        </div>

        <form onSubmit={handleSearch} className="sm:hidden pb-3">
          <div className="relative">
            <span className="material-symbols-outlined absolute left-3 top-1/2 -translate-y-1/2 text-stone-400 text-[18px]">search</span>
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t('nav.search')}
              className="w-full bg-white/10 border-none rounded-full py-2 pl-10 pr-4 text-sm text-white placeholder-stone-400 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
          </div>
        </form>
      </div>
    </nav>
  );
}
