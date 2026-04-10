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
  const [keepSignedIn, setKeepSignedIn] = useState(false);

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
    <div className="min-h-screen bg-white flex flex-col">
      {/* Main content */}
      <div className="flex-1 flex flex-col items-center pt-6 px-4">
        {/* Brand logo */}
        <Link
          to="/"
          className="text-3xl font-extrabold text-brand-900 font-[family-name:var(--font-headline)] tracking-tight mb-5"
        >
          VELLURE
        </Link>

        {/* Sign-in card */}
        <div className="w-full max-w-[350px] border border-outline-variant/40 rounded-lg p-6 shadow-sm bg-white">
          <h2 className="text-2xl font-bold text-on-surface mb-5 font-[family-name:var(--font-headline)]">
            {t('login.title')}
          </h2>

          <form onSubmit={handleSubmit} className="space-y-4">
            {error && (
              <div className="flex items-start gap-2 p-3 bg-red-50 border border-red-300 rounded-md">
                <span className="material-symbols-outlined text-red-600 text-[18px] mt-0.5">warning</span>
                <p className="text-sm text-red-700">{error}</p>
              </div>
            )}

            {/* Email */}
            <div>
              <label className="block text-sm font-bold text-on-surface mb-1">
                {t('login.email')}
              </label>
              <input
                type="email"
                name="email"
                value={formData.email}
                onChange={handleChange}
                required
                className="w-full px-3 py-2 text-sm border border-outline-variant rounded shadow-inner focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
              />
            </div>

            {/* Password */}
            <div>
              <div className="flex items-center justify-between mb-1">
                <label className="block text-sm font-bold text-on-surface">
                  {t('login.password')}
                </label>
                <button
                  type="button"
                  className="text-xs text-brand-500 hover:text-brand-700 hover:underline"
                >
                  Forgot your password?
                </button>
              </div>
              <input
                type="password"
                name="password"
                value={formData.password}
                onChange={handleChange}
                required
                className="w-full px-3 py-2 text-sm border border-outline-variant rounded shadow-inner focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
              />
            </div>

            {/* Submit */}
            <button
              type="submit"
              disabled={isLoading}
              className="w-full bg-brand-500 hover:bg-brand-600 text-white py-2 rounded-lg text-sm font-bold shadow-sm transition-colors disabled:bg-outline-variant disabled:cursor-not-allowed"
            >
              {isLoading ? t('login.signing') : t('login.submit')}
            </button>
          </form>

          {/* Keep me signed in */}
          <div className="mt-4 flex items-start gap-2">
            <input
              type="checkbox"
              id="keepSignedIn"
              checked={keepSignedIn}
              onChange={(e) => setKeepSignedIn(e.target.checked)}
              className="mt-0.5 accent-brand-500"
            />
            <label htmlFor="keepSignedIn" className="text-sm text-on-surface">
              Keep me signed in.{' '}
              <button type="button" className="text-brand-500 hover:text-brand-700 hover:underline text-sm">
                Details
              </button>
            </label>
          </div>

          {/* Legal text */}
          <p className="text-xs text-secondary mt-5 leading-relaxed">
            By continuing, you agree to VELLURE&apos;s{' '}
            <button type="button" className="text-brand-500 hover:text-brand-700 hover:underline">
              Conditions of Use
            </button>{' '}
            and{' '}
            <button type="button" className="text-brand-500 hover:text-brand-700 hover:underline">
              Privacy Notice
            </button>
            .
          </p>
        </div>

        {/* Divider: New to VELLURE? */}
        <div className="w-full max-w-[350px] mt-5">
          <div className="relative flex items-center">
            <div className="flex-grow border-t border-outline-variant/40" />
            <span className="px-3 text-xs text-secondary bg-white">
              New to VELLURE?
            </span>
            <div className="flex-grow border-t border-outline-variant/40" />
          </div>

          <Link
            to="/register"
            className="mt-4 block w-full text-center py-2 text-sm font-semibold text-on-surface bg-surface-low hover:bg-surface-high border border-outline-variant/50 rounded-lg shadow-sm transition-colors"
          >
            {t('login.create')}
          </Link>
        </div>
      </div>

      {/* Light footer */}
      <footer className="mt-10 pt-6 pb-4 border-t border-outline-variant/30 bg-surface-low">
        <div className="flex items-center justify-center gap-6 text-xs text-brand-500 mb-2">
          <button type="button" className="hover:text-brand-700 hover:underline">
            {t('footer.conditions')}
          </button>
          <button type="button" className="hover:text-brand-700 hover:underline">
            {t('footer.privacy')}
          </button>
          <button type="button" className="hover:text-brand-700 hover:underline">
            {t('footer.help')}
          </button>
        </div>
        <p className="text-center text-xs text-secondary">
          {t('footer.copyright')}
        </p>
      </footer>
    </div>
  );
}
