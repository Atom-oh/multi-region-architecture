import { getToken } from './context/AuthContext';

const API_BASE = '/api/v1';

export class ApiError extends Error {
  constructor(status, message, data) {
    super(message);
    this.status = status;
    this.data = data;
  }
}

export async function api(path, options = {}) {
  // Ensure trailing slash before query string to avoid 301 redirects
  let normalizedPath = path;
  const qIdx = normalizedPath.indexOf('?');
  const pathPart = qIdx >= 0 ? normalizedPath.slice(0, qIdx) : normalizedPath;
  const queryPart = qIdx >= 0 ? normalizedPath.slice(qIdx) : '';
  if (!pathPart.endsWith('/')) {
    normalizedPath = pathPart + '/' + queryPart;
  }

  const token = getToken();
  const headers = {
    'Content-Type': 'application/json',
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...options.headers,
  };

  const res = await fetch(`${API_BASE}${normalizedPath}`, { ...options, headers });

  // Handle 401 — auto-logout
  if (res.status === 401) {
    localStorage.removeItem('user');
    localStorage.removeItem('access_token');
    window.location.href = '/login';
    throw new ApiError(401, 'Session expired. Please log in again.');
  }

  // Parse response
  let data;
  try {
    data = await res.json();
  } catch {
    data = null;
  }

  if (!res.ok) {
    const message = data?.message || data?.error || `Request failed (${res.status})`;
    throw new ApiError(res.status, message, data);
  }

  return data;
}

export function mapProduct(p) {
  const cat = p.category;
  const allImages = (p.images || []).filter(u => u && !u.includes('mall.example.com'));
  const imageUrl = allImages[0] || p.image_url || null;
  return {
    id: p.productId || p.product_id || p.id || p._id,
    name: p.name,
    price: p.salePrice || p.price || 0,
    originalPrice: p.price || 0,
    rating: p.rating || 0,
    reviewCount: p.reviewCount || p.review_count || 0,
    category: typeof cat === 'object' ? cat?.slug : cat,
    categoryName: typeof cat === 'object' ? cat?.name : cat,
    imageUrl,
    images: allImages,
    brand: p.brand,
    discount: p.discount || 0,
    description: p.description || '',
    tags: p.tags || [],
    attributes: p.attributes || {},
    stock: p.stock || {},
    status: p.status || 'active',
  };
}

export function mapOrder(o) {
  return {
    id: o.id,
    createdAt: o.created_at || o.createdAt,
    status: o.status,
    items: (o.items || []).map(i => ({
      productId: i.product_id || i.productId,
      name: i.name,
      quantity: i.quantity,
      price: i.price,
    })),
    total: o.total_amount || o.total,
    trackingNumber: o.tracking_number || '',
  };
}
