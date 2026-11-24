import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { type Env, attachment, handle } from "../src/index.ts";
import { FakeBucket, signGrant } from "./support.ts";

const SECRET = "a-test-signing-key-that-is-long-enough-000";
const MOVIE = "2f0c1d6e-8a4b-4c3d-9e5f-0a1b2c3d4e5f";
const ORIGINAL = "7d9e8f10-1a2b-4c3d-8e4f-5a6b7c8d9e0f";
const OTHER_MOVIE = "11111111-2222-4333-8444-555555555555";
const OTHER_ORIGINAL = "66666666-7777-4888-9999-aaaaaaaaaaaa";
const NOW = 1_800_000_000;
const APP = "http://localhost:8765";
const PREFIX = `movies/${MOVIE}/${ORIGINAL}`;

let bucket: FakeBucket;
let env: Env;
let grant: string;

beforeEach(async () => {
  bucket = new FakeBucket();
  bucket.put(`${PREFIX}/master.m3u8`, "#EXTM3U\n720p/index.m3u8\n", "application/vnd.apple.mpegurl");
  bucket.put(`${PREFIX}/720p/index.m3u8`, "#EXTM3U\nseg_00000.m4s\n", "application/vnd.apple.mpegurl");
  bucket.put(`${PREFIX}/720p/init_2.mp4`, "init");
  bucket.put(`${PREFIX}/720p/seg_00000.m4s`, "0123456789", "video/iso.segment");
  bucket.put(`movies/${OTHER_MOVIE}/${OTHER_ORIGINAL}/master.m3u8`, "#EXTM3U\nother\n");
  bucket.put(`originals/${ORIGINAL}`, "the original");
  env = { MEDIA: bucket, PLAYBACK_SIGNING_KEY: SECRET, ALLOWED_ORIGINS: `${APP}, https://app.example` };
  grant = await signGrant(SECRET, { m: MOVIE, o: ORIGINAL, e: NOW + 3600 });
});

function get(path: string, headers: Record<string, string> = {}, method = "GET") {
  return handle(new Request(`https://media.example${path}`, { method, headers }), env, NOW);
}

test("a good grant serves each kind of file", async () => {
  for (const [file, type, body] of [
    ["master.m3u8", "application/vnd.apple.mpegurl", "#EXTM3U\n720p/index.m3u8\n"],
    ["720p/index.m3u8", "application/vnd.apple.mpegurl", "#EXTM3U\nseg_00000.m4s\n"],
    ["720p/init_2.mp4", "video/mp4", "init"],
    ["720p/seg_00000.m4s", "video/iso.segment", "0123456789"],
  ]) {
    const response = await get(`/v1/${grant}/${file}`);
    assert.equal(response.status, 200, file);
    assert.equal(response.headers.get("Content-Type"), type);
    assert.equal(response.headers.get("Cache-Control"), "private, max-age=3600");
    assert.equal(response.headers.get("Accept-Ranges"), "bytes");
    assert.equal(await response.text(), body);
  }
  assert.deepEqual(bucket.requested, [
    `${PREFIX}/master.m3u8`,
    `${PREFIX}/720p/index.m3u8`,
    `${PREFIX}/720p/init_2.mp4`,
    `${PREFIX}/720p/seg_00000.m4s`,
  ]);
});

test("a relative playlist entry keeps the grant", () => {
  // What hls.js and ExoPlayer do with the master playlist's entries.
  const master = new URL(`https://media.example/v1/${grant}/master.m3u8`);
  const quality = new URL("720p/index.m3u8", master);
  const chunk = new URL("seg_00000.m4s", quality);
  assert.equal(chunk.pathname, `/v1/${grant}/720p/seg_00000.m4s`);
});

test("missing, changed and expired grants are refused alike, without reading R2", async () => {
  const expired = await signGrant(SECRET, { m: MOVIE, o: ORIGINAL, e: NOW });
  const otherKey = await signGrant("z".repeat(40), { m: MOVIE, o: ORIGINAL, e: NOW + 60 });
  const [payload, signature] = grant.split(".");
  const swapped = await signGrant("z".repeat(40), { m: OTHER_MOVIE, o: OTHER_ORIGINAL, e: NOW + 60 });
  for (const token of [expired, otherKey, `${swapped.split(".")[0]}.${signature}`, `${payload}.${"A".repeat(43)}`]) {
    const response = await get(`/v1/${token}/master.m3u8`);
    assert.equal(response.status, 403);
    assert.equal(await response.text(), "Not allowed.\n");
    assert.equal(response.headers.get("Cache-Control"), "no-store");
  }
  assert.deepEqual(bucket.requested, []);
});

test("a grant opens its own movie only", async () => {
  const other = await signGrant(SECRET, { m: OTHER_MOVIE, o: OTHER_ORIGINAL, e: NOW + 60 });
  const response = await get(`/v1/${other}/master.m3u8`);
  assert.equal(await response.text(), "#EXTM3U\nother\n");
  assert.deepEqual(bucket.requested, [`movies/${OTHER_MOVIE}/${OTHER_ORIGINAL}/master.m3u8`]);
});

test("only published file names are served", async () => {
  for (const path of [
    `/v1/${grant}/`,
    `/v1/${grant}/original`,
    `/v1/${grant}/../../originals/${ORIGINAL}`,
    `/v1/${grant}/%2e%2e/%2e%2e/originals/${ORIGINAL}`,
    `/v1/${grant}/720p/../../../originals/${ORIGINAL}`,
    `/v1/${grant}/2160p/index.m3u8`,
    `/v1/${grant}/720p/seg_1.ts`,
    `/v1/${grant}/720p/index.m3u8x`,
    `/v1/${grant}/download.mp4`,
    `/v1/${grant}/720p/download.mp4x`,
    `/v1/${grant}/master.m3u8/`,
    `/v1/${grant}//master.m3u8`,
    `/v2/${grant}/master.m3u8`,
    `/v1/master.m3u8`,
    `/movies/${MOVIE}/${ORIGINAL}/master.m3u8`,
    `/originals/${ORIGINAL}`,
    "/",
  ]) {
    assert.equal((await get(path)).status, 404, path);
  }
  assert.deepEqual(bucket.requested, []);
});

test("a quality's download file is an attachment named as asked", async () => {
  bucket.put(`${PREFIX}/720p/download.mp4`, "the whole film", "video/mp4");

  const response = await get(
    `/v1/${grant}/720p/download.mp4?name=${encodeURIComponent("Fast X - VJ Junior - 720p.mp4")}`,
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Content-Type"), "video/mp4");
  assert.equal(
    response.headers.get("Content-Disposition"),
    'attachment; filename="Fast X - VJ Junior - 720p.mp4"',
  );
  assert.equal(await response.text(), "the whole film");
  assert.deepEqual(bucket.requested, [`${PREFIX}/720p/download.mp4`]);
});

test("a download resumes from where it stopped, with a range", async () => {
  bucket.put(`${PREFIX}/720p/download.mp4`, "0123456789", "video/mp4");

  const response = await get(`/v1/${grant}/720p/download.mp4`, { Range: "bytes=4-" });

  assert.equal(response.status, 206);
  assert.equal(response.headers.get("Content-Range"), "bytes 4-9/10");
  assert.match(response.headers.get("Content-Disposition") ?? "", /^attachment;/);
});

test("HEAD on a download file gives its size, for the app to show", async () => {
  bucket.put(`${PREFIX}/720p/download.mp4`, "0123456789", "video/mp4");

  const response = await get(`/v1/${grant}/720p/download.mp4`, {}, "HEAD");

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Content-Length"), "10");
});

test("a download file's name is made safe, and always ends in .mp4", () => {
  assert.equal(attachment(null, "480p"), 'attachment; filename="VeloraUG - 480p.mp4"');
  assert.equal(attachment("Kabaka - S01E02", "720p"), 'attachment; filename="Kabaka - S01E02 - 720p.mp4"');
  assert.equal(
    attachment('../evil"name\r\nX-Header: 1.mp4', "720p"),
    'attachment; filename="evil name X-Header 1.mp4"',
  );
  assert.equal(attachment("???", "360p"), 'attachment; filename="VeloraUG - 360p.mp4"');
});

test("only the download file is an attachment", async () => {
  const response = await get(`/v1/${grant}/720p/init_2.mp4?name=x.mp4`);
  assert.equal(response.headers.get("Content-Disposition"), null);
});

test("a file that isn't in R2 is 404", async () => {
  const response = await get(`/v1/${grant}/1080p/index.m3u8`);
  assert.equal(response.status, 404);
});

test("ranges are passed to R2 and answered with 206", async () => {
  const path = `/v1/${grant}/720p/seg_00000.m4s`;

  const middle = await get(path, { Range: "bytes=2-5" });
  assert.equal(middle.status, 206);
  assert.equal(middle.headers.get("Content-Range"), "bytes 2-5/10");
  assert.equal(middle.headers.get("Content-Length"), "4");
  assert.equal(await middle.text(), "2345");

  const open = await get(path, { Range: "bytes=7-" });
  assert.equal(open.headers.get("Content-Range"), "bytes 7-9/10");
  assert.equal(await open.text(), "789");

  const suffix = await get(path, { Range: "bytes=-3" });
  assert.equal(suffix.headers.get("Content-Range"), "bytes 7-9/10");
  assert.equal(await suffix.text(), "789");

  assert.equal((await get(path, { Range: "bytes=50-" })).status, 416);
});

test("a matching ETag answers 304", async () => {
  const path = `/v1/${grant}/master.m3u8`;
  const etag = (await get(path)).headers.get("ETag")!;
  const again = await get(path, { "If-None-Match": etag });
  assert.equal(again.status, 304);
});

test("HEAD gives the size without the body", async () => {
  const response = await get(`/v1/${grant}/720p/seg_00000.m4s`, {}, "HEAD");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Content-Length"), "10");
  assert.equal(await response.text(), "");
});

test("the web app's origin gets CORS headers", async () => {
  const response = await get(`/v1/${grant}/master.m3u8`, { Origin: APP });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), APP);
  assert.equal(response.headers.get("Vary"), "Origin");
  assert.match(response.headers.get("Access-Control-Expose-Headers")!, /Content-Range/);
});

test("other origins are refused, even with a good grant", async () => {
  for (const origin of ["https://evil.example", "null", "http://localhost:8766"]) {
    const response = await get(`/v1/${grant}/master.m3u8`, { Origin: origin });
    assert.equal(response.status, 403, origin);
    assert.equal(response.headers.get("Access-Control-Allow-Origin"), null);
  }
  assert.deepEqual(bucket.requested, []);
});

test("without an Origin, as from ExoPlayer, the grant alone decides", async () => {
  const response = await get(`/v1/${grant}/master.m3u8`);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), null);
});

test("a preflight from the web app is allowed, with Range", async () => {
  const response = await get(
    `/v1/${grant}/720p/seg_00000.m4s`,
    { Origin: APP, "Access-Control-Request-Method": "GET", "Access-Control-Request-Headers": "range" },
    "OPTIONS",
  );
  assert.equal(response.status, 204);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), APP);
  assert.equal(response.headers.get("Access-Control-Allow-Headers"), "Range");
});

test("only GET, HEAD and OPTIONS", async () => {
  for (const method of ["POST", "PUT", "DELETE"]) {
    const response = await get(`/v1/${grant}/master.m3u8`, {}, method);
    assert.equal(response.status, 405, method);
  }
});

test("without a long enough signing key, nothing is served", async () => {
  env.PLAYBACK_SIGNING_KEY = "short";
  assert.equal((await get(`/v1/${grant}/master.m3u8`)).status, 503);
  env.PLAYBACK_SIGNING_KEY = undefined as unknown as string;
  assert.equal((await get(`/v1/${grant}/master.m3u8`)).status, 503);
  assert.deepEqual(bucket.requested, []);
});
