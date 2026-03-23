const API_BASE = '/api/v1';

export async function api(path, options = {}) {
  try {
    const res = await fetch(`${API_BASE}${path}`, {
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
  return {
    id: p.productId || p.id || p._id,
    name: p.name,
    price: p.salePrice || p.price,
    originalPrice: p.price,
    rating: p.rating || 0,
    reviewCount: p.reviewCount || p.review_count || 0,
    category: typeof cat === 'object' ? cat?.slug : cat,
    categoryName: typeof cat === 'object' ? cat?.name : cat,
    imageUrl: p.images?.[0] || p.image_url,
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
