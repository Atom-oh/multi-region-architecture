import { createContext, useContext, useState, useEffect } from 'react';
import { useAuth } from './AuthContext';
import { api } from '../api';

const CartContext = createContext(null);

export function CartProvider({ children }) {
  const { user } = useAuth();
  const [cartCount, setCartCount] = useState(0);

  useEffect(() => {
    const fetchCartCount = async () => {
      if (!user?.id) return;
      try {
        const data = await api(`/carts/${user.id}`);
        const items = data.items || [];
        setCartCount(items.reduce((sum, item) => sum + item.quantity, 0));
      } catch (err) {
        console.error('Failed to fetch cart count:', err);
      }
    };
    fetchCartCount();
  }, [user?.id]);

  const updateCartCount = (count) => {
    setCartCount(count);
  };

  const incrementCart = () => {
    setCartCount((prev) => prev + 1);
  };

  const decrementCart = () => {
    setCartCount((prev) => Math.max(0, prev - 1));
  };

  return (
    <CartContext.Provider value={{ cartCount, updateCartCount, incrementCart, decrementCart }}>
      {children}
    </CartContext.Provider>
  );
}

export function useCart() {
  const context = useContext(CartContext);
  if (!context) {
    throw new Error('useCart must be used within a CartProvider');
  }
  return context;
}
