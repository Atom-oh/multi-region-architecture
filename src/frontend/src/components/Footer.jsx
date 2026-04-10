import { Link } from 'react-router-dom';
import { useI18n } from '../context/I18nContext';

export default function Footer() {
  const { t } = useI18n();

  return (
    <footer className="bg-brand-900 text-white/60 mt-16">
      <div className="max-w-7xl mx-auto px-4 md:px-6 py-12">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-8">
          <div>
            <h3 className="text-white text-lg font-extrabold font-[family-name:var(--font-headline)] tracking-tight mb-4">
              VELLURE
            </h3>
            <p className="text-sm leading-relaxed">
              {t('footer.desc')}
            </p>
          </div>

          <div>
            <h4 className="text-white font-semibold mb-4 text-sm uppercase tracking-wider">{t('footer.shop')}</h4>
            <ul className="space-y-2.5 text-sm">
              <li><Link to="/products" className="hover:text-white transition-colors">{t('footer.allProducts')}</Link></li>
              <li><Link to="/products?category=electronics" className="hover:text-white transition-colors">{t('cat.electronics')}</Link></li>
              <li><Link to="/products?category=fashion" className="hover:text-white transition-colors">{t('cat.fashion')}</Link></li>
              <li><Link to="/products?category=home" className="hover:text-white transition-colors">{t('cat.home')}</Link></li>
            </ul>
          </div>

          <div>
            <h4 className="text-white font-semibold mb-4 text-sm uppercase tracking-wider">{t('footer.support')}</h4>
            <ul className="space-y-2.5 text-sm">
              <li><Link to="/orders" className="hover:text-white transition-colors">{t('footer.orderTracking')}</Link></li>
              <li><Link to="/returns" className="hover:text-white transition-colors">{t('footer.returnsExchanges')}</Link></li>
              <li><a href="#" className="hover:text-white transition-colors">{t('footer.faq')}</a></li>
              <li><a href="#" className="hover:text-white transition-colors">{t('footer.contactUs')}</a></li>
            </ul>
          </div>

          <div>
            <h4 className="text-white font-semibold mb-4 text-sm uppercase tracking-wider">{t('footer.about')}</h4>
            <ul className="space-y-2.5 text-sm">
              <li><a href="#" className="hover:text-white transition-colors">{t('footer.privacy')}</a></li>
              <li><a href="#" className="hover:text-white transition-colors">{t('footer.conditions')}</a></li>
              <li><a href="#" className="hover:text-white transition-colors">{t('footer.ads')}</a></li>
              <li><a href="#" className="hover:text-white transition-colors">{t('footer.help')}</a></li>
            </ul>
          </div>
        </div>

        <div className="border-t border-white/10 mt-10 pt-8 text-center">
          <p className="text-white/30 text-[10px] uppercase tracking-[0.2em] mb-2">{t('footer.tagline')}</p>
          <p className="text-white/50 text-xs">{t('footer.copyright')}</p>
        </div>
      </div>
    </footer>
  );
}
