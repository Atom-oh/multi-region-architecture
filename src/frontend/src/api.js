const API_BASE = '/api/v1';

export async function api(path, options = {}) {
  try {
    // Ensure trailing slash before query string to avoid 301 redirects
    let normalizedPath = path;
    const qIdx = normalizedPath.indexOf('?');
    const pathPart = qIdx >= 0 ? normalizedPath.slice(0, qIdx) : normalizedPath;
    const queryPart = qIdx >= 0 ? normalizedPath.slice(qIdx) : '';
    if (!pathPart.endsWith('/')) {
      normalizedPath = pathPart + '/' + queryPart;
    }
    const res = await fetch(`${API_BASE}${normalizedPath}`, {
      headers: { 'Content-Type': 'application/json', ...options.headers },
      ...options,
    });
    return res.json();
  } catch (error) {
    console.error('API Error:', error);
    throw error;
  }
}

export function mapProduct(p) {
  const cat = p.category;
  const rawImage = p.images?.[0] || p.image_url || null;
  const imageUrl = rawImage && !rawImage.includes('mall.example.com') ? rawImage : null;
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
    brand: p.brand,
    discount: p.discount || 0,
    description: p.description || '',
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
