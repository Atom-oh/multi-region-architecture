import { useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { useI18n } from '../context/I18nContext';
import { api } from '../api';
import StarRating from './StarRating';

/**
 * Modal form for creating or editing a product review.
 * Props:
 *   productId - required for create mode
 *   initialData - if provided, form operates in edit mode (PUT)
 *   onClose - callback to close the modal
 *   onSuccess - callback after successful submission
 */
export default function ReviewForm({ productId, initialData, onClose, onSuccess }) {
  const { t } = useI18n();
  const { user } = useAuth();
  const isEdit = !!initialData;

  const [rating, setRating] = useState(initialData?.rating || 0);
  const [title, setTitle] = useState(initialData?.title || '');
  const [body, setBody] = useState(initialData?.content || '');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (rating === 0) {
      setError(t('review.ratingRequired'));
      return;
    }
    setSubmitting(true);
    setError('');

    try {
      if (isEdit) {
        await api(`/reviews/${initialData.id}?user_id=${encodeURIComponent(user.id)}`, {
          method: 'PUT',
          body: JSON.stringify({ rating, title, body }),
        });
      } else {
        await api('/reviews', {
          method: 'POST',
          body: JSON.stringify({
            user_id: user.id,
            product_id: productId,
            rating,
            title,
            body,
          }),
        });
      }
      onSuccess?.();
      onClose();
    } catch (err) {
      setError(err.message || t('review.submitFailed'));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm" onClick={onClose}>
      <div
        className="bg-white rounded-xl shadow-xl max-w-lg w-full mx-4 p-6"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-5">
          <h2 className="text-lg font-bold text-on-surface font-[family-name:var(--font-headline)]">
            {isEdit ? t('review.editReview') : t('review.writeReview')}
          </h2>
          <button onClick={onClose} className="text-secondary hover:text-on-surface transition-colors">
            <span className="material-symbols-outlined">close</span>
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {/* Star Rating Input */}
          <div>
            <label className="block text-sm font-semibold text-on-surface mb-2">{t('review.rating')}</label>
            <StarRating interactive value={rating} onChange={setRating} size={32} />
          </div>

          {/* Title */}
          <div>
            <label className="block text-sm font-semibold text-on-surface mb-1">{t('review.title')}</label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={t('review.titlePlaceholder')}
              maxLength={200}
              required
              className="w-full px-3 py-2 text-sm border border-outline-variant/50 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent"
            />
          </div>

          {/* Body */}
          <div>
            <label className="block text-sm font-semibold text-on-surface mb-1">{t('review.body')}</label>
            <textarea
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder={t('review.bodyPlaceholder')}
              maxLength={5000}
              required
              rows={4}
              className="w-full px-3 py-2 text-sm border border-outline-variant/50 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent resize-none"
            />
          </div>

          {error && (
            <p className="text-sm text-red-600">{error}</p>
          )}

          {/* Actions */}
          <div className="flex gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 py-2.5 text-sm font-semibold text-on-surface border border-outline-variant/50 rounded-full hover:bg-surface-low transition-colors"
            >
              {t('review.cancel')}
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="flex-1 py-2.5 text-sm font-bold text-white bg-brand-500 rounded-full hover:bg-brand-600 transition-colors disabled:opacity-50"
            >
              {submitting ? t('review.submitting') : (isEdit ? t('review.update') : t('review.submit'))}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
