/** Format price in Korean Won */
export function formatPrice(price) {
  if (price == null) return '';
  return `₩${Number(price).toLocaleString('ko-KR')}`;
}

/** Validate email format */
export function validateEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

/** Validate phone number (Korean format) */
export function validatePhone(phone) {
  return /^01[0-9]-?\d{3,4}-?\d{4}$/.test(phone.replace(/\s/g, ''));
}

/**
 * Validate password strength:
 * - min 8 chars
 * - at least one uppercase, one lowercase, one digit
 */
export function validatePassword(pw) {
  if (pw.length < 8) return 'Password must be at least 8 characters.';
  if (!/[A-Z]/.test(pw)) return 'Password must include an uppercase letter.';
  if (!/[a-z]/.test(pw)) return 'Password must include a lowercase letter.';
  if (!/[0-9]/.test(pw)) return 'Password must include a number.';
  return null;
}

/** Validate credit card number (basic Luhn-adjacent: 13-19 digits) */
export function validateCardNumber(num) {
  const digits = num.replace(/\s|-/g, '');
  return /^\d{13,19}$/.test(digits);
}

/** Validate MM/YY expiry and check not expired */
export function validateExpiry(expiry) {
  const match = expiry.match(/^(0[1-9]|1[0-2])\/(\d{2})$/);
  if (!match) return false;
  const month = parseInt(match[1], 10);
  const year = 2000 + parseInt(match[2], 10);
  const now = new Date();
  return year > now.getFullYear() || (year === now.getFullYear() && month >= now.getMonth() + 1);
}

/** Validate CVC (3-4 digits) */
export function validateCVC(cvc) {
  return /^\d{3,4}$/.test(cvc);
}
