import { useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { api } from '../api';
import { useI18n } from '../context/I18nContext';

export default function ProfilePage() {
  const { t } = useI18n();
  const { user, login } = useAuth();

  const [formData, setFormData] = useState({
    name: user?.name || '',
    email: user?.email || '',
    phone: user?.phone || '',
    address: user?.address || '',
  });
  const [isEditing, setIsEditing] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setIsSaving(true);

    try {
      await api(`/profiles/${user.id}`, {
        method: 'PUT',
        body: JSON.stringify(formData),
      });
      login({ ...user, ...formData });
      setIsEditing(false);
    } catch (error) {
      console.error('Profile update failed:', error);
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="max-w-3xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold text-slate-800 mb-8">{t('profile.title')}</h1>

      <div className="bg-white rounded-lg shadow-sm">
        {/* Profile Header */}
        <div className="p-6 border-b flex items-center gap-4">
          <div className="w-20 h-20 bg-blue-100 rounded-full flex items-center justify-center">
            <span className="text-3xl font-bold text-blue-500">
              {user?.name?.charAt(0) || '?'}
            </span>
          </div>
          <div>
            <h2 className="text-xl font-bold text-slate-800">{user?.name}</h2>
            <p className="text-slate-500">{user?.email}</p>
            <p className="text-sm text-slate-400 mt-1">ID: {user?.id}</p>
          </div>
        </div>

        {/* Profile Form */}
        <form onSubmit={handleSubmit} className="p-6">
          <div className="space-y-6">
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">
                {t('register.name')}
              </label>
              {isEditing ? (
                <input
                  type="text"
                  name="name"
                  value={formData.name}
                  onChange={handleChange}
                  className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              ) : (
                <p className="px-4 py-3 bg-slate-50 rounded-lg text-slate-800">{formData.name}</p>
              )}
            </div>

            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">
                {t('register.email')}
              </label>
              {isEditing ? (
                <input
                  type="email"
                  name="email"
                  value={formData.email}
                  onChange={handleChange}
                  className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              ) : (
                <p className="px-4 py-3 bg-slate-50 rounded-lg text-slate-800">{formData.email}</p>
              )}
            </div>

            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">
                {t('register.phone')}
              </label>
              {isEditing ? (
                <input
                  type="tel"
                  name="phone"
                  value={formData.phone}
                  onChange={handleChange}
                  placeholder="010-0000-0000"
                  className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              ) : (
                <p className="px-4 py-3 bg-slate-50 rounded-lg text-slate-800">
                  {formData.phone || '-'}
                </p>
              )}
            </div>

            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">
                {t('checkout.address')}
              </label>
              {isEditing ? (
                <input
                  type="text"
                  name="address"
                  value={formData.address}
                  onChange={handleChange}
                  className="w-full px-4 py-3 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              ) : (
                <p className="px-4 py-3 bg-slate-50 rounded-lg text-slate-800">
                  {formData.address || '-'}
                </p>
              )}
            </div>
          </div>

          <div className="flex gap-3 mt-8">
            {isEditing ? (
              <>
                <button
                  type="button"
                  onClick={() => setIsEditing(false)}
                  className="flex-1 px-4 py-3 border border-slate-300 rounded-lg font-medium text-slate-700 hover:bg-slate-50 transition-colors"
                >
                  {t('profile.cancel')}
                </button>
                <button
                  type="submit"
                  disabled={isSaving}
                  className="flex-1 bg-blue-500 text-white px-4 py-3 rounded-lg font-medium hover:bg-blue-600 transition-colors disabled:bg-slate-300"
                >
                  {isSaving ? t('common.loading') : t('profile.save')}
                </button>
              </>
            ) : (
              <button
                type="button"
                onClick={() => setIsEditing(true)}
                className="flex-1 bg-blue-500 text-white px-4 py-3 rounded-lg font-medium hover:bg-blue-600 transition-colors"
              >
                {t('profile.edit')}
              </button>
            )}
          </div>
        </form>
      </div>

      {/* Additional Settings */}
      <div className="bg-white rounded-lg shadow-sm mt-6 divide-y">
        <button disabled className="w-full flex items-center justify-between p-4 opacity-50 cursor-not-allowed">
          <span className="text-slate-800">{t('profile.changePw')}</span>
          <span className="text-xs text-slate-400 bg-slate-100 px-2 py-0.5 rounded">{t('profile.comingSoon')}</span>
        </button>
        <button disabled className="w-full flex items-center justify-between p-4 opacity-50 cursor-not-allowed">
          <span className="text-slate-800">{t('profile.notifications')}</span>
          <span className="text-xs text-slate-400 bg-slate-100 px-2 py-0.5 rounded">{t('profile.comingSoon')}</span>
        </button>
        <button disabled className="w-full flex items-center justify-between p-4 opacity-50 cursor-not-allowed">
          <span className="text-red-400">{t('profile.deleteAccount')}</span>
          <span className="text-xs text-slate-400 bg-slate-100 px-2 py-0.5 rounded">{t('profile.comingSoon')}</span>
        </button>
      </div>
    </div>
  );
}
