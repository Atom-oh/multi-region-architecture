import { useState, useEffect, useMemo } from 'react';
import { useSearchParams } from 'react-router-dom';
import ProductCard from '../components/ProductCard';
import { api, mapProduct } from '../api';
import { useI18n } from '../context/I18nContext';

const DEFAULT_CATEGORY_KEYS = [
  { id: 'all', key: 'products.all' },
  { id: 'electronics', key: 'cat.electronics' },
  { id: 'fashion', key: 'cat.fashion' },
  { id: 'home', key: 'cat.home' },
  { id: 'beauty', key: 'cat.beauty' },
  { id: 'sports', key: 'cat.sports' },
];

const PAGE_SIZE = 20;

export default function ProductsPage() {
  const { t } = useI18n();
  const [searchParams, setSearchParams] = useSearchParams();
  const [products, setProducts] = useState([]);
  const [total, setTotal] = useState(0);
  const [apiCategories, setApiCategories] = useState(null);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState(searchParams.get('q') || '');

  const selectedCategory = searchParams.get('category') || 'all';
  const currentPage = parseInt(searchParams.get('page') || '1', 10);

  const defaultCategories = useMemo(
    () => DEFAULT_CATEGORY_KEYS.map(c => ({ id: c.id, name: t(c.key) })),
    [t]
  );

  const categories = apiCategories || defaultCategories;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  useEffect(() => {
    api('/products/categories').then(data => {
      const cats = (data.categories || data || []).map(c => ({
        id: typeof c === 'object' ? (c.slug || c.id) : c,
        name: typeof c === 'object' ? c.name : c,
      }));
      if (cats.length > 0) {
        setApiCategories([{ id: 'all', name: t('products.all') }, ...cats]);
      }
    }).catch(() => {});
  }, [t]);

  useEffect(() => {
    const fetchProducts = async () => {
      setLoading(true);
      try {
        const skip = (currentPage - 1) * PAGE_SIZE;
        const params = new URLSearchParams();
        if (selectedCategory !== 'all') params.set('category', selectedCategory);
        if (searchQuery) params.set('q', searchQuery);
        params.set('skip', String(skip));
        params.set('limit', String(PAGE_SIZE));
        const data = await api(`/products?${params}`);
        setProducts((data.products || data || []).map(mapProduct));
        setTotal(data.total ?? (data.products || data || []).length);
      } catch (error) {
        console.error('Failed to load products:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchProducts();
  }, [searchQuery, selectedCategory, currentPage]);

  const handleCategoryChange = (category) => {
    const params = new URLSearchParams(searchParams);
    if (category === 'all') {
      params.delete('category');
    } else {
      params.set('category', category);
    }
    params.delete('page');
    setSearchParams(params);
  };

  const handleSearch = (e) => {
    e.preventDefault();
    const params = new URLSearchParams(searchParams);
    if (searchQuery) {
      params.set('q', searchQuery);
    } else {
      params.delete('q');
    }
    params.delete('page');
    setSearchParams(params);
  };

  const goToPage = (page) => {
    const params = new URLSearchParams(searchParams);
    if (page <= 1) {
      params.delete('page');
    } else {
      params.set('page', String(page));
    }
    setSearchParams(params);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const getPageNumbers = () => {
    const pages = [];
    const maxVisible = 5;
    let start = Math.max(1, currentPage - Math.floor(maxVisible / 2));
    let end = Math.min(totalPages, start + maxVisible - 1);
    if (end - start + 1 < maxVisible) {
      start = Math.max(1, end - maxVisible + 1);
    }
    for (let i = start; i <= end; i++) pages.push(i);
    return pages;
  };

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold text-slate-800 mb-8">{t('products.title')}</h1>

      {/* Search Bar */}
      <form onSubmit={handleSearch} className="mb-6">
        <div className="relative max-w-xl">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder={t('products.search')}
            className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
          <button
            type="submit"
            className="absolute right-2 top-1/2 -translate-y-1/2 bg-blue-500 text-white px-4 py-2 rounded-lg hover:bg-blue-600 transition-colors"
          >
            {t('products.searchBtn')}
          </button>
        </div>
      </form>

      {/* Category Filter */}
      <div className="flex flex-wrap gap-2 mb-8">
        {categories.map((category) => (
          <button
            key={category.id}
            onClick={() => handleCategoryChange(category.id)}
            className={`px-4 py-2 rounded-full text-sm font-medium transition-colors ${
              selectedCategory === category.id
                ? 'bg-blue-500 text-white'
                : 'bg-slate-100 text-slate-700 hover:bg-slate-200'
            }`}
          >
            {category.name}
          </button>
        ))}
      </div>

      {/* Results Info */}
      <div className="flex items-center justify-between mb-4">
        <p className="text-slate-500">
          {searchQuery && `"${searchQuery}" `}
          {t('products.count', { count: total })}
          {totalPages > 1 && ` · ${currentPage} / ${totalPages} ${t('products.page') || '페이지'}`}
        </p>
      </div>

      {/* Product Grid */}
      {loading ? (
        <div className="text-center py-12">
          <p className="text-slate-500 text-lg">{t('common.loading')}</p>
        </div>
      ) : products.length === 0 ? (
        <div className="text-center py-12">
          <p className="text-slate-500 text-lg">{t('products.noResults')}</p>
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            {products.map((product) => (
              <ProductCard key={product.id} product={product} />
            ))}
          </div>

          {/* Pagination */}
          {totalPages > 1 && (
            <nav className="flex items-center justify-center gap-1 mt-10">
              <button
                onClick={() => goToPage(currentPage - 1)}
                disabled={currentPage <= 1}
                className="px-3 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-30 disabled:cursor-not-allowed text-slate-600 hover:bg-slate-100"
              >
                ← {t('products.prev') || '이전'}
              </button>

              {getPageNumbers()[0] > 1 && (
                <>
                  <button onClick={() => goToPage(1)} className="w-10 h-10 rounded-lg text-sm font-medium text-slate-600 hover:bg-slate-100">1</button>
                  {getPageNumbers()[0] > 2 && <span className="px-1 text-slate-400">…</span>}
                </>
              )}

              {getPageNumbers().map((page) => (
                <button
                  key={page}
                  onClick={() => goToPage(page)}
                  className={`w-10 h-10 rounded-lg text-sm font-medium transition-colors ${
                    page === currentPage
                      ? 'bg-blue-500 text-white'
                      : 'text-slate-600 hover:bg-slate-100'
                  }`}
                >
                  {page}
                </button>
              ))}

              {getPageNumbers().at(-1) < totalPages && (
                <>
                  {getPageNumbers().at(-1) < totalPages - 1 && <span className="px-1 text-slate-400">…</span>}
                  <button onClick={() => goToPage(totalPages)} className="w-10 h-10 rounded-lg text-sm font-medium text-slate-600 hover:bg-slate-100">{totalPages}</button>
                </>
              )}

              <button
                onClick={() => goToPage(currentPage + 1)}
                disabled={currentPage >= totalPages}
                className="px-3 py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-30 disabled:cursor-not-allowed text-slate-600 hover:bg-slate-100"
              >
                {t('products.next') || '다음'} →
              </button>
            </nav>
          )}
        </>
      )}
    </div>
  );
}
