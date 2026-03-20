export default function ReviewCard({ review }) {
  const renderStars = (rating) => {
    const fullStars = Math.floor(rating);
    const emptyStars = 5 - fullStars;
    return (
      <span className="text-yellow-400">
        {'★'.repeat(fullStars)}
        <span className="text-slate-300">{'☆'.repeat(emptyStars)}</span>
      </span>
    );
  };

  const formatDate = (dateString) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('ko-KR', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  };

  return (
    <div className="bg-white rounded-lg p-4 border border-slate-200">
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 bg-slate-200 rounded-full flex items-center justify-center">
            <span className="text-sm font-medium text-slate-600">
              {review.userName?.charAt(0) || '익'}
            </span>
          </div>
          <span className="font-medium text-slate-800">{review.userName || '익명'}</span>
        </div>
        <span className="text-sm text-slate-500">{formatDate(review.createdAt)}</span>
      </div>

      <div className="mb-2">
        {renderStars(review.rating)}
      </div>

      <p className="text-slate-600">{review.content}</p>

      {review.images && review.images.length > 0 && (
        <div className="flex gap-2 mt-3">
          {review.images.map((image, index) => (
            <div key={index} className="w-16 h-16 rounded-lg overflow-hidden bg-slate-100">
              <img src={image} alt="" className="w-full h-full object-cover" />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
