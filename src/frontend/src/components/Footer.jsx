import { Link } from 'react-router-dom';

export default function Footer() {
  return (
    <footer className="bg-brand-900 text-white/60 mt-16">
      <div className="max-w-7xl mx-auto px-4 md:px-6 py-12">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-8">
          <div>
            <h3 className="text-white text-lg font-extrabold font-[family-name:var(--font-headline)] tracking-tight mb-4">
              Architectural Curator
            </h3>
            <p className="text-sm leading-relaxed">
              A new standard in global shopping. Fast, reliable experiences anywhere in the world.
            </p>
          </div>

          <div>
            <h4 className="text-white font-semibold mb-4 text-sm uppercase tracking-wider">Shop</h4>
            <ul className="space-y-2.5 text-sm">
              <li><Link to="/products" className="hover:text-white transition-colors">All Products</Link></li>
              <li><Link to="/products?category=electronics" className="hover:text-white transition-colors">Electronics</Link></li>
              <li><Link to="/products?category=fashion" className="hover:text-white transition-colors">Fashion</Link></li>
              <li><Link to="/products?category=home" className="hover:text-white transition-colors">Home & Living</Link></li>
            </ul>
          </div>

          <div>
            <h4 className="text-white font-semibold mb-4 text-sm uppercase tracking-wider">Support</h4>
            <ul className="space-y-2.5 text-sm">
              <li><Link to="/orders" className="hover:text-white transition-colors">Order Tracking</Link></li>
              <li><Link to="/returns" className="hover:text-white transition-colors">Returns & Exchanges</Link></li>
              <li><a href="#" className="hover:text-white transition-colors">FAQ</a></li>
              <li><a href="#" className="hover:text-white transition-colors">Contact Us</a></li>
            </ul>
          </div>

          <div>
            <h4 className="text-white font-semibold mb-4 text-sm uppercase tracking-wider">About</h4>
            <ul className="space-y-2.5 text-sm">
              <li><a href="#" className="hover:text-white transition-colors">Privacy Notice</a></li>
              <li><a href="#" className="hover:text-white transition-colors">Conditions of Use</a></li>
              <li><a href="#" className="hover:text-white transition-colors">Interest-Based Ads</a></li>
              <li><a href="#" className="hover:text-white transition-colors">Help</a></li>
            </ul>
          </div>
        </div>

        <div className="border-t border-white/10 mt-10 pt-8 text-center">
          <p className="text-white/30 text-[10px] uppercase tracking-[0.2em] mb-2">Curated for the visionary</p>
          <p className="text-white/50 text-xs">&copy; 2024 Architectural Curator. All rights reserved.</p>
        </div>
      </div>
    </footer>
  );
}
