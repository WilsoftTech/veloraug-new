import assert from 'node:assert/strict';
import { test } from 'node:test';

import { allowedReturnTarget } from '../src/returnTarget.js';

const origin = 'https://veloraug-auth-dev.pages.dev';

test('allows the web and Android callbacks', () => {
  for (const target of [
    'http://localhost:8765/auth.html',
    `${origin}/auth/callback/android`,
  ]) {
    assert.equal(allowedReturnTarget(target, origin), target);
  }
});

test('refuses everything else', () => {
  for (const target of [
    null,
    '',
    'https://example.com/',
    'http://localhost:8765/auth.html?x=1',
    'http://localhost:8765.example.com/auth.html',
    `${origin}/auth/callback/android/`,
    `${origin}/login`,
    '//example.com',
    'javascript:alert(1)',
  ]) {
    assert.equal(allowedReturnTarget(target, origin), null);
  }
});
