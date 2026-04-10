import { Link } from 'react-router-dom';
import { useI18n } from '../context/I18nContext';

export default function Footer() {
  const { t } = useI18n();

  return (
    <footer className="bg-surface-low mt-16">
      <div className="max-w-7xl mx-auto px-4 md:px-6 py-12">
        <div className="flex flex-col md:flex-row md:justify-between gap-10">
          {/* Left side: Brand */}
          <div className="md:max-w-xs">
            <h3 className="text-on-surface text-2xl font-bold font-[family-name:var(--font-headline)] tracking-tight mb-3">
              VELLURE
            </h3>
            <p className="text-secondary text-sm leading-relaxed mb-4">
              {t('footer.desc')}
            </p>
            <p className="text-outline text-xs">
              {t('footer.copyright')}
            </p>
          </div>

          {/* Right side: 3 link columns */}
          <div className="flex flex-wrap gap-12 md:gap-16">
            {/* Collection */}
            <div>
              <h4 className="text-on-surface font-semibold mb-4 text-sm uppercase tracking-wider">
                {t('footer.collection')}
              </h4>
              <ul className="space-y-2.5 text-sm text-secondary">
                <li><Link to="/products?category=living-room" className="hover:text-on-surface transition-colors">{t('footer.livingRoom')}</Link></li>
                <li><Link to="/products?category=bedroom" className="hover:text-on-surface transition-colors">{t('footer.bedroom')}</Link></li>
                <li><Link to="/products?category=workspace" className="hover:text-on-surface transition-colors">{t('footer.workspace')}</Link></li>
                <li><Link to="/products?category=lighting" className="hover:text-on-surface transition-colors">{t('footer.lighting')}</Link></li>
              </ul>
            </div>

            {/* About */}
            <div>
              <h4 className="text-on-surface font-semibold mb-4 text-sm uppercase tracking-wider">
                {t('footer.about')}
              </h4>
              <ul className="space-y-2.5 text-sm text-secondary">
                <li><a href="#" className="hover:text-on-surface transition-colors">{t('footer.theStudio')}</a></li>
                <li><a href="#" className="hover:text-on-surface transition-colors">{t('footer.ourDesigners')}</a></li>
                <li><a href="#" className="hover:text-on-surface transition-colors">{t('footer.editorial')}</a></li>
                <li><a href="#" className="hover:text-on-surface transition-colors">{t('footer.impact')}</a></li>
              </ul>
            </div>

            {/* Support */}
            <div>
              <h4 className="text-on-surface font-semibold mb-4 text-sm uppercase tracking-wider">
                {t('footer.support')}
              </h4>
              <ul className="space-y-2.5 text-sm text-secondary">
                <li><a href="#" className="hover:text-on-surface transition-colors">{t('footer.privacy')}</a></li>
                <li><a href="#" className="hover:text-on-surface transition-colors">{t('footer.termsOfService')}</a></li>
                <li><a href="#" className="hover:text-on-surface transition-colors">{t('footer.accessibility')}</a></li>
                <li><a href="#" className="hover:text-on-surface transition-colors">{t('footer.contactUs')}</a></li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
}
