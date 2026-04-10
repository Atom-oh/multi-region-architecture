import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { api } from '../api';
import { validateEmail, validatePassword, validatePhone } from '../utils';
import { useI18n } from '../context/I18nContext';

export default function RegisterPage() {
  const { t } = useI18n();
  const { login } = useAuth();
  const navigate = useNavigate();

  const [formData, setFormData] = useState({
    name: '', email: '', password: '', passwordConfirm: '', phone: '',
    agreeTerms: false, agreePrivacy: false,
  });
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  const handleChange = (e) => {
    const { name, value, type, checked } = e.target;
    setFormData(prev => ({ ...prev, [name]: type === 'checkbox' ? checked : value }));
    setError('');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    if (!validateEmail(formData.email)) {
      setError(t('login.invalidEmail'));
      return;
    }
    const pwError = validatePassword(formData.password);
    if (pwError) { setError(pwError); return; }
    if (formData.password !== formData.passwordConfirm) {
      setError(t('register.pwMismatch'));
      return;
    }
    if (formData.phone && !validatePhone(formData.phone)) {
      setError(t('register.invalidPhone'));
      return;
    }
    if (!formData.agreeTerms || !formData.agreePrivacy) {
      setError(t('register.agreeTerms'));
      return;
    }

    setIsLoading(true);
    try {
      const data = await api('/users/register', {
        method: 'POST',
        body: JSON.stringify({
          name: formData.name,
          email: formData.email,
          password: formData.password,
          phone: formData.phone,
        }),
      });
      const token = data.access_token || data.token || '';
      login(
        {
          id: data.id || data.user_id,
          name: data.name || formData.name,
          email: data.email || formData.email,
          phone: data.phone || formData.phone,
          address: '',
        },
        token,
      );
      navigate('/');
    } catch (err) {
      setError(err.message || t('register.failed'));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-surface py-12 px-4">
      <div className="max-w-md w-full">
        <div className="text-center mb-8">
          <Link to="/" className="text-3xl font-extrabold text-brand-900 font-[family-name:var(--font-headline)]">
            VELLURE
          </Link>
          <p className="text-secondary mt-2">{t('register.title')}</p>
        </div>

        <div className="bg-white rounded-xl shadow-sm p-8">
          <form onSubmit={handleSubmit} className="space-y-5">
            {error && (
              <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-red-600 text-sm">{error}</div>
            )}

            <div>
              <label className="block text-sm font-medium text-on-surface mb-1">{t('register.name')} <span className="text-red-500">*</span></label>
              <input type="text" name="name" value={formData.name} onChange={handleChange} required placeholder="Your name"
                className="w-full px-4 py-3 rounded-lg border border-outline-variant focus:outline-none focus:ring-2 focus:ring-brand-500" />
            </div>

            <div>
              <label className="block text-sm font-medium text-on-surface mb-1">{t('register.email')} <span className="text-red-500">*</span></label>
              <input type="email" name="email" value={formData.email} onChange={handleChange} required placeholder="you@example.com"
                className="w-full px-4 py-3 rounded-lg border border-outline-variant focus:outline-none focus:ring-2 focus:ring-brand-500" />
            </div>

            <div>
              <label className="block text-sm font-medium text-on-surface mb-1">{t('register.password')} <span className="text-red-500">*</span></label>
              <input type="password" name="password" value={formData.password} onChange={handleChange} required placeholder={t('register.pwPlaceholder')}
                className="w-full px-4 py-3 rounded-lg border border-outline-variant focus:outline-none focus:ring-2 focus:ring-brand-500" />
            </div>

            <div>
              <label className="block text-sm font-medium text-on-surface mb-1">{t('register.confirmPw')} <span className="text-red-500">*</span></label>
              <input type="password" name="passwordConfirm" value={formData.passwordConfirm} onChange={handleChange} required placeholder={t('register.rePw')}
                className="w-full px-4 py-3 rounded-lg border border-outline-variant focus:outline-none focus:ring-2 focus:ring-brand-500" />
            </div>

            <div>
              <label className="block text-sm font-medium text-on-surface mb-1">{t('register.phone')}</label>
              <input type="tel" name="phone" value={formData.phone} onChange={handleChange} placeholder="010-1234-5678"
                className="w-full px-4 py-3 rounded-lg border border-outline-variant focus:outline-none focus:ring-2 focus:ring-brand-500" />
            </div>

            <div className="space-y-3 pt-4 border-t border-outline-variant/20">
              <label className="flex items-start gap-2">
                <input type="checkbox" name="agreeTerms" checked={formData.agreeTerms} onChange={handleChange}
                  className="w-4 h-4 text-brand-500 rounded mt-0.5" />
                <span className="text-sm text-secondary"><span className="text-red-500">{t('register.required')}</span> {t('register.terms')}</span>
              </label>
              <label className="flex items-start gap-2">
                <input type="checkbox" name="agreePrivacy" checked={formData.agreePrivacy} onChange={handleChange}
                  className="w-4 h-4 text-brand-500 rounded mt-0.5" />
                <span className="text-sm text-secondary"><span className="text-red-500">{t('register.required')}</span> {t('register.privacy')}</span>
              </label>
            </div>

            <button type="submit" disabled={isLoading}
              className="w-full bg-brand-500 text-white py-3 rounded-lg font-bold hover:bg-brand-700 transition-colors disabled:bg-outline-variant">
              {isLoading ? t('register.creating') : t('register.submit')}
            </button>
          </form>
        </div>

        <p className="text-center text-secondary mt-6">
          {t('register.hasAccount')}{' '}
          <Link to="/login" className="text-brand-500 hover:text-brand-700 font-semibold">{t('register.signIn')}</Link>
        </p>
      </div>
    </div>
  );
}
