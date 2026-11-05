import assert from 'node:assert/strict';
import { test } from 'node:test';

// The SDK's real mapping, as adapter-core imports it. @neon/auth is pinned, so this
// fails on an upgrade that changes where the server's code is kept.
import { t as createHttpResponseError } from '../node_modules/@neon/auth/dist/better-auth-helpers.js';
import {
  describeScopes,
  errorMessage,
  isExpiredRequest,
  isLocalAddress,
  isUnverifiedEmail,
  requestHasExpired,
  returnToAppHref,
} from '../src/messages.js';

const origin = 'https://veloraug-auth-dev.pages.dev';

function serverError(status, body) {
  return createHttpResponseError(
    new Response(JSON.stringify(body), { status, statusText: 'Bad Request' }),
  );
}

test('an expired request is recognised from what the server sends', async () => {
  const error = await serverError(400, { error: 'invalid_signature' });
  assert.equal(isExpiredRequest(error), true);
});

test('other failures are not treated as an expired request', async () => {
  const error = await serverError(400, {
    message: 'Invalid OTP',
    code: 'INVALID_OTP',
  });
  assert.equal(isExpiredRequest(error), false);
});

test('a wrong password and an unknown address get the same message', async () => {
  const error = await serverError(401, {
    message: 'Invalid email or password',
    code: 'INVALID_EMAIL_OR_PASSWORD',
  });
  assert.equal(errorMessage(error), 'That email or password is incorrect.');
});

test('a code the server refuses offers a new one', async () => {
  for (const code of ['INVALID_OTP', 'OTP_EXPIRED', 'TOO_MANY_ATTEMPTS']) {
    const error = await serverError(400, { message: 'x', code });
    assert.match(errorMessage(error), /new one/, code);
  }
});

test('an unverified account is recognised', async () => {
  const error = await serverError(403, {
    message: 'Email not verified',
    code: 'EMAIL_NOT_VERIFIED',
  });
  assert.equal(isUnverifiedEmail(error), true);
});

test('messages never repeat the SDK label or server text', async () => {
  for (const [status, body] of [
    [400, { error: 'invalid_signature' }],
    [400, { message: 'Invalid OTP', code: 'INVALID_OTP' }],
    [400, { message: '[body.email] Invalid email address', code: 'VALIDATION_ERROR' }],
    [500, { message: 'database detail', code: 'INTERNAL' }],
  ]) {
    const text = errorMessage(await serverError(status, body));
    assert.doesNotMatch(text, /validation_failed|HTTP 400|\[body|database detail/);
  }
});

test('invalid input asks the person to check it', async () => {
  const error = await serverError(400, {
    message: '[body.email] Invalid email address',
    code: 'VALIDATION_ERROR',
  });
  assert.equal(errorMessage(error), 'Check what you entered and try again.');
});

test('too many requests and a lost connection have their own messages', async () => {
  const limited = await serverError(429, { message: 'Too many requests' });
  assert.match(errorMessage(limited), /Wait a few minutes/);
  assert.match(errorMessage(new TypeError('Failed to fetch')), /connection/);
});

test('a request has expired once its time has passed', () => {
  assert.equal(requestHasExpired('?exp=1000&sig=a', 1000), true);
  assert.equal(requestHasExpired('?exp=1000&sig=a', 999), false);
});

test('a request with no readable expiry is left to the server to judge', () => {
  assert.equal(requestHasExpired('?sig=a', 1000), false);
  assert.equal(requestHasExpired('?exp=soon', 1000), false);
});

test('the way back keeps the state, so the app can match it', () => {
  const callback = `${origin}/auth/callback/android`;
  const search = new URLSearchParams({
    redirect_uri: callback,
    state: 'a b&c',
  });
  assert.equal(
    returnToAppHref(`?${search}`, origin),
    `${callback}?error=login_required&state=a+b%26c`,
  );
});

test('the way back refuses an address that is not allowed', () => {
  const search = new URLSearchParams({
    redirect_uri: 'https://example.com/steal',
    state: 's',
  });
  assert.equal(returnToAppHref(`?${search}`, origin), null);
  assert.equal(returnToAppHref('?state=s', origin), null);
});

test('scopes are described in plain words, and unknown ones are still shown', () => {
  assert.deepEqual(describeScopes('openid email offline_access custom'), [
    'Confirm who you are',
    'See your email address',
    'Keep you signed in',
    'custom',
  ]);
  assert.deepEqual(describeScopes(null), []);
});

test('local addresses are recognised for the consent warning', () => {
  assert.equal(isLocalAddress('localhost:8765'), true);
  assert.equal(isLocalAddress('127.0.0.1:8765'), true);
  assert.equal(isLocalAddress('veloraug-auth-dev.pages.dev'), false);
  assert.equal(isLocalAddress('localhost.example.com'), false);
});
