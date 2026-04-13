import { useState } from 'react';

/**
 * Shared star rating component with display and interactive modes.
 * Uses Material Symbols Outlined icons with VELLURE brand-500 color.
 */
export default function StarRating({ rating = 0, size = 18, interactive = false, value = 0, onChange }) {
  const [hoverValue, setHoverValue] = useState(0);

  if (interactive) {
    const displayValue = hoverValue || value;
    return (
      <span className="inline-flex items-center gap-0.5">
        {[1, 2, 3, 4, 5].map(star => (
          <button
            key={star}
            type="button"
            onMouseEnter={() => setHoverValue(star)}
            onMouseLeave={() => setHoverValue(0)}
            onClick={() => onChange?.(star)}
            className="cursor-pointer transition-transform hover:scale-110"
          >
            <span
              className={`material-symbols-outlined ${star <= displayValue ? 'text-brand-500' : 'text-outline-variant'}`}
              style={{ fontSize: size, fontVariationSettings: star <= displayValue ? "'FILL' 1" : "'FILL' 0" }}
            >
              star
            </span>
          </button>
        ))}
      </span>
    );
  }

  const full = Math.floor(rating || 0);
  const hasHalf = (rating || 0) % 1 >= 0.5;
  const empty = 5 - full - (hasHalf ? 1 : 0);

  return (
    <span className="inline-flex items-center gap-0.5 text-brand-500">
      {[...Array(full)].map((_, i) => (
        <span key={`f${i}`} className="material-symbols-outlined" style={{ fontSize: size, fontVariationSettings: "'FILL' 1" }}>star</span>
      ))}
      {hasHalf && <span className="material-symbols-outlined" style={{ fontSize: size }}>star_half</span>}
      {[...Array(empty)].map((_, i) => (
        <span key={`e${i}`} className="material-symbols-outlined text-outline-variant" style={{ fontSize: size }}>star</span>
      ))}
    </span>
  );
}
