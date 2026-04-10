import { useState } from 'react';
import { Link, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { api } from '../api';
import { validateEmail } from '../utils';
import { useI18n } from '../context/I18nContext';

export default function LoginPage() {
  const { t } = useI18n();
  const { login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const from = location.state?.from?.pathname || '/';

  const [formData, setFormData] = useState({ email: '', password: '' });
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
    setError('');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    if (!validateEmail(formData.email)) {
      setError(t('login.invalidEmail'));
      return;
    }
    if (!formData.password) {
      setError(t('login.noPassword'));
      return;
    }

    setIsLoading(true);
    try {
      const data = await api('/users/login', {
        method: 'POST',
        body: JSON.stringify({ email: formData.email, password: formData.password }),
      });
      const u = data.user || data;
      const token = data.access_token || data.token || '';
      login(
        {
          id: u.user_id || u.id,
          name: u.name || formData.email.split('@')[0],
          email: u.email || formData.email,
          phone: u.phone || '',
          address: u.address || '',
        },
        token,
      );
      navigate(from, { replace: true });
    } catch (err) {
      setError(err.message || t('login.failed'));
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
          <p className="text-secondary mt-2">{t('login.title')}</p>
        </div>

        <div className="bg-white rounded-xl shadow-sm p-8">
          <form onSubmit={handleSubmit} className="space-y-6">
            {error && (
              <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-red-600 text-sm">
                {error}
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-on-surface mb-1">{t('login.email')}</label>
              <input
                type="email"
                name="email"
                value={formData.email}
                onChange={handleChange}
                required
                placeholder="you@example.com"
                className="w-full px-4 py-3 rounded-lg border border-outline-variant focus:outline-none focus:ring-2 focus:ring-brand-500"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-on-surface mb-1">{t('login.password')}</label>
              <input
                type="password"
                name="password"
                value={formData.password}
                onChange={handleChange}
                required
                placeholder="Enter password"
                className="w-full px-4 py-3 rounded-lg border border-outline-variant focus:outline-none focus:ring-2 focus:ring-brand-500"
              />
            </div>

            <button
              type="submit"
              disabled={isLoading}
              className="w-full bg-brand-500 text-white py-3 rounded-lg font-bold hover:bg-brand-700 transition-colors disabled:bg-outline-variant"
            >
              {isLoading ? t('login.signing') : t('login.submit')}
            </button>
          </form>
        </div>

        <p className="text-center text-secondary mt-6">
          {t('login.noAccount')}{' '}
          <Link to="/register" className="text-brand-500 hover:text-brand-700 font-semibold">
            {t('login.create')}
          </Link>
        </p>
      </div>
    </div>
  );
}
