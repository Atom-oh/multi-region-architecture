import { createContext, useContext, useState } from 'react';

const CartContext = createContext(null);

export function CartProvider({ children }) {
  const [cartCount, setCartCount] = useState(3);

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
