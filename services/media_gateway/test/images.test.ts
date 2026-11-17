import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { type Env, handle } from "../src/index.ts";
import { looksLike } from "../src/images.ts";
import { FakeBucket, signGrant, signUploadGrant } from "./support.ts";

const SECRET = "a-test-signing-key-that-is-long-enough-000";
const NOW = 1_800_000_000;
const APP = "http://localhost:8765";
const EDITION = "2f0c1d6e-8a4b-4c3d-9e5f-0a1b2c3d4e5f";
const PATH = `posters/${EDITION}/abcdefghijklmnop.jpg`;
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0]);

let bucket: FakeBucket;
let env: Env;

beforeEach(() => {
  bucket = new FakeBucket();
  env = { MEDIA: bucket, PLAYBACK_SIGNING_KEY: SECRET, ALLOWED_ORIGINS: APP };
});

function upload(grant: string, body: Uint8Array, type = "image/jpeg") {
  return handle(
    new Request(`https://media.example/i/${grant}`, {
      method: "PUT",
      headers: { "Content-Type": type, Origin: APP },
      body,
    }),
    env,
    NOW,
  );
}

function get(path: string, method = "GET") {
  return handle(new Request(`https://media.example${path}`, { method }), env, NOW);
}

test("a good upload grant stores the image at its path", async () => {
  const grant = await signUploadGrant(SECRET, { p: PATH, t: "image/jpeg", e: NOW + 600 });

  const response = await upload(grant, JPEG);

  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { path: PATH });
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), APP);
  assert.deepEqual(bucket.written, [PATH]);
  assert.deepEqual(bucket.objects.get(PATH)?.contentType, "image/jpeg");
});

test("expired, changed, playback and mismatched grants are refused", async () => {
  const expired = await signUploadGrant(SECRET, { p: PATH, t: "image/jpeg", e: NOW });
  const playback = await signGrant(SECRET, { p: PATH, t: "image/jpeg", e: NOW + 600 });
  const wrongType = await signUploadGrant(SECRET, { p: PATH, t: "image/png", e: NOW + 600 });
  const badPath = await signUploadGrant(SECRET, {
    p: `movies/${EDITION}/abcdefghijklmnop.jpg`,
    t: "image/jpeg",
    e: NOW + 600,
  });
  const otherKey = await signUploadGrant("x".repeat(40), {
    p: PATH,
    t: "image/jpeg",
    e: NOW + 600,
  });

  for (const grant of [expired, playback, wrongType, badPath, otherKey]) {
    assert.equal((await upload(grant, JPEG)).status, 403);
  }
  assert.deepEqual(bucket.written, []);
});

test("the type, size and content must match", async () => {
  const grant = await signUploadGrant(SECRET, { p: PATH, t: "image/jpeg", e: NOW + 600 });

  assert.equal((await upload(grant, JPEG, "image/png")).status, 415);
  assert.equal((await upload(grant, PNG)).status, 415);
  const big = new Uint8Array(2_000_001);
  big.set(JPEG);
  assert.equal((await upload(grant, big)).status, 413);
  assert.deepEqual(bucket.written, []);
});

test("uploaded images are served publicly, and nothing else under /i/", async () => {
  bucket.put(PATH, JPEG, "image/jpeg");
  bucket.put(`movies/${EDITION}/abcdefghijklmnop.jpg`, "secret");

  const response = await get(`/i/${PATH}`);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Content-Type"), "image/jpeg");
  assert.match(response.headers.get("Cache-Control") ?? "", /public/);
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), JPEG);

  for (const path of [
    `/i/movies/${EDITION}/abcdefghijklmnop.jpg`,
    `/i/originals/${EDITION}`,
    `/i/posters/${EDITION}/../x.jpg`,
    `/i/posters/${EDITION}/short.jpg`,
    `/i/vjs/${EDITION}/abcdefghijklmnop.gif`,
  ]) {
    assert.equal((await get(path)).status, 404, path);
  }
  assert.equal((await get(`/i/vjs/${EDITION}/abcdefghijklmnop.png`)).status, 404);
});

test("a preflight for an upload allows PUT with Content-Type", async () => {
  const response = await handle(
    new Request(`https://media.example/i/x.y`, {
      method: "OPTIONS",
      headers: { Origin: APP, "Access-Control-Request-Method": "PUT" },
    }),
    env,
    NOW,
  );
  assert.equal(response.status, 204);
  assert.equal(response.headers.get("Access-Control-Allow-Methods"), "GET, HEAD, PUT");
  assert.equal(response.headers.get("Access-Control-Allow-Headers"), "Content-Type");
});

test("without a signing key, uploads are off but nothing is written", async () => {
  env.PLAYBACK_SIGNING_KEY = "short";
  assert.equal((await upload("a.b", JPEG)).status, 404);
  const grant = await signUploadGrant(SECRET, { p: PATH, t: "image/jpeg", e: NOW + 600 });
  assert.equal((await upload(grant, JPEG)).status, 503);
  assert.deepEqual(bucket.written, []);
});

test("image types are told by their first bytes", () => {
  assert.equal(looksLike("image/jpeg", JPEG), true);
  assert.equal(looksLike("image/png", PNG), true);
  const webp = new TextEncoder().encode("RIFF\0\0\0\0WEBPVP8 ");
  assert.equal(looksLike("image/webp", webp), true);
  assert.equal(looksLike("image/png", JPEG), false);
  assert.equal(looksLike("image/gif", JPEG), false);
});
