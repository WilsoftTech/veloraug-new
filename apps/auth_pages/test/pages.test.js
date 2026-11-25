// The sign-in pages' redesign, Phase 7: the brand mark, the icons, and that
// nothing about signing in changed. The pages are rendered on the server
// through Vite, so their markup can be checked without a browser.
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { createServer } from 'vite';

import { backdropImages } from '../src/backdrop.js';

const root = fileURLToPath(new URL('..', import.meta.url));
const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const app = read('src/App.jsx');

function pngSize(path) {
  const bytes = readFileSync(new URL(`../public${path}`, import.meta.url));
  assert.equal(bytes.toString('latin1', 1, 4), 'PNG', `${path} isn't a PNG`);
  return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
}

// --- Files ---------------------------------------------------------------------

test("the old drawn mark is gone, and the app's own mark is used", () => {
  assert.doesNotMatch(app, /M4 14H32L60 88H40Z/);
  assert.doesNotMatch(app, /brand-mark-left|brand-mark-right/);
  assert.match(app, /\/brand\/velora-mark-48\.png 1x, \/brand\/velora-mark-96\.png 2x/);
  assert.deepEqual(pngSize('/brand/velora-mark-48.png'), [48, 48]);
  assert.deepEqual(pngSize('/brand/velora-mark-96.png'), [96, 96]);
});

test('the page has the favicon, home-screen icon and theme colour', () => {
  const html = read('index.html');
  for (const path of ['/brand/favicon.png', '/brand/apple-touch-icon.png']) {
    assert.match(html, new RegExp(`href="${path}"`));
    assert.ok(existsSync(new URL(`../public${path}`, import.meta.url)), path);
  }
  assert.match(html, /<meta name="theme-color" content="#0e1014" \/>/);
  assert.match(html, /<meta name="robots" content="noindex" \/>/);
});

test('the Content-Security-Policy is unchanged', () => {
  assert.match(
    read('public/_headers'),
    /Content-Security-Policy: default-src 'self'; connect-src 'self' https:\/\/\*\.aws\.neon\.tech; frame-ancestors 'none'; base-uri 'none'; form-action 'self'\n/,
  );
});

test('the backdrop loads only pictures from this site', () => {
  for (const path of backdropImages) {
    assert.match(path, /^\/backdrop\/[\w.-]+\.(webp|jpg|png)$/);
    assert.ok(existsSync(new URL(`../public${path}`, import.meta.url)), path);
  }
});

// Every way the pages sign in, and every sentence they say, is still there.
test('no handler, address or wording changed', () => {
  for (const call of [
    'authClient.oauth2.continue({ selected: true })',
    'authClient.emailOtp.sendVerificationOtp({',
    'authClient.emailOtp.verifyEmail({',
    'authClient.getSession()',
    'authClient.signIn.email({ email, password })',
    'authClient.signUp.email({',
    'authClient.forgetPassword.emailOtp({ email })',
    'authClient.emailOtp.resetPassword({',
    'authClient.oauth2.publicClient({',
    'authClient.oauth2.consent({ accept })',
    'authClient.signOut()',
    "withQuery('/login')",
    "withQuery('/sign-up')",
    "withQuery('/reset')",
    'window.location.assign(`${target}?signed_out=1`)',
  ]) {
    assert.ok(app.includes(call), `missing ${call}`);
  }
  for (const words of [
    'We sent a new code. Check your email.',
    'Enter your code',
    'It lasts about 15 minutes.',
    'Send a new code',
    'Start signing in from the VeloraUG app.',
    'Create an account',
    'Forgot password',
    'Password, at least 8 characters',
    'Create account',
    'Back to sign in',
    'If that address has an account, we sent it a code.',
    'Password changed',
    'Sign in with your new password.',
    'Choose a new password',
    'New password, at least 8 characters',
    'Change password',
    'If that address has an account, we sent it a new code.',
    'Send reset code',
    'Allow access?',
    'This app runs on this computer. Allow it only if you started it',
    'Signed out. You can close this page.',
    'This signs you out of VeloraUG in this browser.',
    'Return to VeloraUG',
    'Open VeloraUG',
    'This sign-in has timed out',
    'Back to VeloraUG',
    'Open this site from the VeloraUG app.',
  ]) {
    assert.ok(app.includes(words), `missing "${words}"`);
  }
});

// --- Rendered ------------------------------------------------------------------

let server;
let render;

before(async () => {
  server = await createServer({
    root,
    configFile: `${root}vite.config.js`,
    server: { middlewareMode: true, hmr: false },
    appType: 'custom',
    logLevel: 'silent',
  });
  ({ render } = await server.ssrLoadModule('/test/render.jsx'));
});

after(async () => {
  await server?.close();
  delete globalThis.window;
});

const future = 'sig=preview&exp=9999999999';

test('each field has its own label, and a hint it names', () => {
  const html = render(`/sign-up?${future}`);
  const inputs = [...html.matchAll(/<input ([^>]*)>/g)].map((m) => m[1]);
  assert.equal(inputs.length, 3);
  for (const input of inputs) {
    const id = input.match(/id="([^"]+)"/)[1];
    assert.match(html, new RegExp(`<label for="${id}">`));
    assert.match(input, new RegExp(`aria-describedby="${id}-hint"`));
    assert.match(html, new RegExp(`<p class="field-hint" id="${id}-hint">`));
    assert.match(input, /placeholder=" "/);
    assert.match(input, /required/);
  }
  assert.match(html, /<label for="[^"]+">Display name<\/label>/);
  assert.match(html, /<label for="[^"]+">Password, at least 8 characters<\/label>/);
});

test('a password field starts hidden, with a Show password toggle', () => {
  const html = render(`/login?${future}`);
  assert.match(html, /type="password"/);
  assert.match(
    html,
    /<button type="button" class="field-toggle" aria-label="Show password" aria-pressed="false"/,
  );
  // The toggle sits outside the form's submit, so it never signs in.
  assert.equal((html.match(/<button(?![^>]*type="button")/g) ?? []).length, 1);
});

test('the card has the mark, and the page a backdrop and a footer', () => {
  const html = render(`/login?${future}`);
  assert.match(html, /<img class="brand-mark" src="\/brand\/velora-mark-48\.png"[^>]* alt=""/);
  assert.match(html, /<div class="backdrop" aria-hidden="true">/);
  assert.equal((html.match(/class="backdrop-tile /g) ?? []).length, 24);
  assert.match(html, /<footer class="footer">VeloraUG · Movies and series translated/);
  assert.match(html, /<main><h1>Sign in<\/h1>/);
});

test('an expired request still shows the timed-out page', () => {
  const html = render('/login?sig=preview&exp=1');
  assert.match(html, /This sign-in has timed out/);
  assert.doesNotMatch(html, /<input/);
});

test('without a signed request, it says to start from the app', () => {
  assert.match(render('/login'), /Start signing in from the VeloraUG app\./);
  assert.match(render('/somewhere'), /Open this site from the VeloraUG app\./);
});
