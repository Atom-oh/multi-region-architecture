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
