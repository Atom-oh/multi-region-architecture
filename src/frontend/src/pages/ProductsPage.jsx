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

export default function ProductsPage() {
  const { t } = useI18n();
  const [searchParams, setSearchParams] = useSearchParams();
  const [products, setProducts] = useState([]);
  const [apiCategories, setApiCategories] = useState(null);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState(searchParams.get('q') || '');

  const selectedCategory = searchParams.get('category') || 'all';

  const defaultCategories = useMemo(
    () => DEFAULT_CATEGORY_KEYS.map(c => ({ id: c.id, name: t(c.key) })),
    [t]
  );

  const categories = apiCategories || defaultCategories;

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
        const params = new URLSearchParams();
        if (selectedCategory !== 'all') params.set('category', selectedCategory);
        if (searchQuery) params.set('q', searchQuery);
        params.set('limit', '20');
        const data = await api(`/products?${params}`);
        setProducts((data.products || data || []).map(mapProduct));
      } catch (error) {
        console.error('Failed to load products:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchProducts();
  }, [searchQuery, selectedCategory]);

  const handleCategoryChange = (category) => {
    const params = new URLSearchParams(searchParams);
    if (category === 'all') {
      params.delete('category');
    } else {
      params.set('category', category);
    }
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
    setSearchParams(params);
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
      <p className="text-slate-500 mb-4">
        {searchQuery && `"${searchQuery}" `}
        {t('products.count', { count: products.length })}
      </p>

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
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {products.map((product) => (
            <ProductCard key={product.id} product={product} />
          ))}
        </div>
      )}
    </div>
  );
}
