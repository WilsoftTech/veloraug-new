import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const tokensCss = read('../src/tokens.css');
const styleCss = read('../src/style.css');

function token(name) {
  const match = tokensCss.match(new RegExp(`--velora-color-${name}:\\s*(#[0-9a-f]{6});`));
  assert.ok(match, `missing token ${name}`);
  return match[1];
}

function luminance(hex) {
  const channels = [1, 3, 5].map((start) => {
    const value = Number.parseInt(hex.slice(start, start + 2), 16) / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function contrast(a, b) {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (light + 0.05) / (dark + 0.05);
}

test('text used on the pages meets WCAG AA on its background', () => {
  for (const [text, background] of [
    ['text-primary', 'canvas'],
    ['text-primary', 'surface'],
    ['text-secondary', 'surface'],
    ['accent-text', 'surface'],
    ['on-accent', 'accent'],
    ['on-accent', 'accent-hover'],
    ['on-accent', 'accent-pressed'],
    ['text-primary', 'info-container'],
    ['text-primary', 'surface-raised'],
    ['text-primary', 'surface-overlay'],
  ]) {
    const ratio = contrast(token(text), token(background));
    assert.ok(ratio >= 4.5, `${text} on ${background} is only ${ratio.toFixed(2)}:1`);
  }
});

test('control edges and the focus ring reach 3:1', () => {
  for (const [line, background] of [
    ['outline', 'canvas'],
    ['outline', 'surface'],
    ['focus-ring', 'surface'],
    ['focus-ring', 'accent'],
  ]) {
    const ratio = contrast(token(line), token(background));
    assert.ok(ratio >= 3, `${line} on ${background} is only ${ratio.toFixed(2)}:1`);
  }
});

test('the stylesheet uses tokens and only tokens for colour', () => {
  assert.equal(styleCss.match(/#[0-9a-fA-F]{3,8}\b/g), null);
});

test('every token the stylesheet uses is defined', () => {
  for (const [, name] of styleCss.matchAll(/var\((--velora-[a-z-]+)\)/g)) {
    assert.ok(tokensCss.includes(`${name}:`), `undefined token ${name}`);
  }
});

test('styling loads nothing the Content-Security-Policy would block', () => {
  for (const css of [tokensCss, styleCss]) {
    assert.doesNotMatch(css, /url\(/);
    assert.doesNotMatch(css, /https?:/);
  }
});

test('focus stays visible and reduced motion is honoured', () => {
  assert.match(styleCss, /:focus-visible\s*\{\s*outline:/);
  assert.match(styleCss, /prefers-reduced-motion: reduce/);
  assert.doesNotMatch(styleCss, /outline:\s*(none|0)/);
});
