import { allowedReturnTarget } from './returnTarget.js';

// The SDK labels several unrelated failures "validation_failed", so messages come
// from the server's own code, which it keeps on error.error. Server text is never
// shown, because it isn't written for the people using these pages.
const MESSAGES = {
  INVALID_EMAIL_OR_PASSWORD: 'That email or password is incorrect.',
  INVALID_EMAIL: 'Check that your email address is correct.',
  VALIDATION_ERROR: 'Check what you entered and try again.',
  PASSWORD_TOO_SHORT: 'Use a password of at least 8 characters.',
  PASSWORD_TOO_LONG: 'That password is too long. Use a shorter one.',
  INVALID_OTP: 'That code is incorrect or has expired. Check it, or send a new one.',
  OTP_EXPIRED: 'That code has expired. Send a new one.',
  TOO_MANY_ATTEMPTS: 'Too many tries with that code. Send a new one.',
};

const GENERIC_MESSAGE = 'Something went wrong. Please try again.';
const OFFLINE_MESSAGE =
  "We couldn't reach the sign-in service. Check your connection and try again.";
const RATE_LIMITED_MESSAGE = 'Too many attempts. Wait a few minutes and try again.';

// The body has a code when Better Auth answers, and an error for OAuth failures.
export function serverCode(error) {
  return error?.error?.code ?? error?.error?.error ?? null;
}

export function isExpiredRequest(error) {
  return serverCode(error) === 'invalid_signature';
}

export function isUnverifiedEmail(error) {
  return serverCode(error) === 'EMAIL_NOT_VERIFIED';
}

export function errorMessage(error) {
  const message = MESSAGES[serverCode(error)];
  if (message) return message;
  const status = error?.error?.status ?? error?.status;
  if (status === 429) return RATE_LIMITED_MESSAGE;
  if (status === undefined) return OFFLINE_MESSAGE;
  return GENERIC_MESSAGE;
}

// Neon's signed request carries its expiry, in seconds, as `exp`.
export function requestHasExpired(search, nowSeconds) {
  const expiry = Number(new URLSearchParams(search).get('exp'));
  return Number.isFinite(expiry) && expiry > 0 && expiry <= nowSeconds;
}

// Sends the browser back to the app with an OAuth error, so the app stops waiting.
// The address is unverified once a request expires, so it must be on the allow list.
export function returnToAppHref(search, pageOrigin) {
  const params = new URLSearchParams(search);
  const target = allowedReturnTarget(params.get('redirect_uri'), pageOrigin);
  if (!target) return null;
  const query = new URLSearchParams({ error: 'login_required' });
  const state = params.get('state');
  if (state) query.set('state', state);
  return `${target}?${query}`;
}

const SCOPE_DESCRIPTIONS = {
  openid: 'Confirm who you are',
  email: 'See your email address',
  profile: 'See your name',
  offline_access: 'Keep you signed in',
};

export function describeScopes(scope) {
  return (scope ?? '')
    .split(' ')
    .filter(Boolean)
    .map((name) => SCOPE_DESCRIPTIONS[name] ?? name);
}

export function isLocalAddress(host) {
  return /^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(host);
}
