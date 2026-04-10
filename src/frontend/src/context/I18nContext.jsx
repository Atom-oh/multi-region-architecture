import { createContext, useContext, useState } from 'react';
import { translations } from '../i18n/translations';

const I18nContext = createContext(null);

export function I18nProvider({ children }) {
  const [lang, setLang] = useState(() => {
    return localStorage.getItem('lang') || 'ko';
  });

  const toggleLang = () => {
    setLang(prev => {
      const next = prev === 'ko' ? 'en' : 'ko';
      localStorage.setItem('lang', next);
      return next;
    });
  };

  const setLanguage = (l) => {
    localStorage.setItem('lang', l);
    setLang(l);
  };

  const t = (key, params) => {
    let text = translations[lang]?.[key] || translations['en']?.[key] || key;
    if (params) {
      Object.entries(params).forEach(([k, v]) => {
        text = text.replace(`{${k}}`, v);
      });
    }
    return text;
  };

  return (
    <I18nContext.Provider value={{ lang, t, toggleLang, setLanguage }}>
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n() {
  const context = useContext(I18nContext);
  if (!context) throw new Error('useI18n must be used within I18nProvider');
  return context;
}
