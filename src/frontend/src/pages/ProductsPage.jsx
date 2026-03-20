import { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import ProductCard from '../components/ProductCard';

const ALL_PRODUCTS = [
  { id: 'PRD-001', name: '삼성 갤럭시 S24 Ultra', price: 1890000, rating: 4.8, reviewCount: 1234, category: 'electronics' },
  { id: 'PRD-002', name: 'LG 그램 17인치 노트북', price: 2190000, rating: 4.7, reviewCount: 856, category: 'electronics' },
  { id: 'PRD-003', name: '나이키 에어맥스 97', price: 219000, rating: 4.6, reviewCount: 2341, category: 'fashion' },
  { id: 'PRD-004', name: '다이슨 V15 무선청소기', price: 1290000, rating: 4.9, reviewCount: 567, category: 'home' },
  { id: 'PRD-005', name: '애플 맥북 프로 14', price: 2890000, rating: 4.9, reviewCount: 1892, category: 'electronics' },
  { id: 'PRD-006', name: '소니 WH-1000XM5 헤드폰', price: 449000, rating: 4.8, reviewCount: 3421, category: 'electronics' },
  { id: 'PRD-007', name: '무지 린넨 셔츠', price: 59000, rating: 4.5, reviewCount: 892, category: 'fashion' },
  { id: 'PRD-008', name: '필립스 에어프라이어 XXL', price: 329000, rating: 4.7, reviewCount: 1567, category: 'home' },
  { id: 'PRD-009', name: '아이패드 프로 12.9', price: 1729000, rating: 4.9, reviewCount: 2134, category: 'electronics' },
  { id: 'PRD-010', name: '구찌 마몬트 백', price: 2890000, rating: 4.8, reviewCount: 456, category: 'fashion' },
  { id: 'PRD-011', name: '발뮤다 토스터', price: 329000, rating: 4.6, reviewCount: 789, category: 'home' },
  { id: 'PRD-012', name: '아디다스 울트라부스트', price: 239000, rating: 4.7, reviewCount: 1823, category: 'fashion' },
  { id: 'PRD-013', name: '삼성 QLED 75인치 TV', price: 3490000, rating: 4.8, reviewCount: 432, category: 'electronics' },
  { id: 'PRD-014', name: '르크루제 무쇠냄비 세트', price: 890000, rating: 4.9, reviewCount: 567, category: 'home' },
  { id: 'PRD-015', name: '버버리 트렌치코트', price: 3290000, rating: 4.7, reviewCount: 234, category: 'fashion' },
  { id: 'PRD-016', name: '로지텍 MX Master 3S', price: 149000, rating: 4.8, reviewCount: 2345, category: 'electronics' },
];

const CATEGORIES = [
  { id: 'all', name: '전체' },
  { id: 'electronics', name: '전자제품' },
  { id: 'fashion', name: '패션' },
  { id: 'home', name: '홈/리빙' },
  { id: 'beauty', name: '뷰티' },
  { id: 'sports', name: '스포츠' },
];

export default function ProductsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState(searchParams.get('q') || '');

  const selectedCategory = searchParams.get('category') || 'all';

  useEffect(() => {
    const fetchProducts = async () => {
      setLoading(true);
      try {
        // In production: const data = await api(`/search?q=${searchQuery}&category=${selectedCategory}`);
        await new Promise(resolve => setTimeout(resolve, 300));

        let filtered = ALL_PRODUCTS;

        if (selectedCategory !== 'all') {
          filtered = filtered.filter(p => p.category === selectedCategory);
        }

        if (searchQuery) {
          const query = searchQuery.toLowerCase();
          filtered = filtered.filter(p =>
            p.name.toLowerCase().includes(query) ||
            p.category.toLowerCase().includes(query)
          );
        }

        setProducts(filtered);
      } catch (error) {
        console.error('데이터를 불러올 수 없습니다:', error);
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
      <h1 className="text-3xl font-bold text-slate-800 mb-8">상품 목록</h1>

      {/* Search Bar */}
      <form onSubmit={handleSearch} className="mb-6">
        <div className="relative max-w-xl">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="상품명으로 검색..."
            className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
          <button
            type="submit"
            className="absolute right-2 top-1/2 -translate-y-1/2 bg-blue-500 text-white px-4 py-2 rounded-lg hover:bg-blue-600 transition-colors"
          >
            검색
          </button>
        </div>
      </form>

      {/* Category Filter */}
      <div className="flex flex-wrap gap-2 mb-8">
        {CATEGORIES.map((category) => (
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
        {searchQuery && `"${searchQuery}" 검색 결과: `}
        총 {products.length}개의 상품
      </p>

      {/* Product Grid */}
      {loading ? (
        <div className="text-center py-12">
          <p className="text-slate-500 text-lg">로딩 중...</p>
        </div>
      ) : products.length === 0 ? (
        <div className="text-center py-12">
          <p className="text-slate-500 text-lg">검색 결과가 없습니다.</p>
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
