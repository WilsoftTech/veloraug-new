// Milestone 10: grants bound to a playback session are honoured only while
// the API says the session is live.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { beforeEach, test } from "node:test";

import { importSigningKey, verifyGrant } from "../src/grant.ts";
import { type Env, handle } from "../src/index.ts";
import { forgetSessions, signCheck } from "../src/sessions.ts";
import { FakeBucket, signGrant } from "./support.ts";

const SECRET = "a-test-signing-key-that-is-long-enough-000";
const MOVIE = "2f0c1d6e-8a4b-4c3d-9e5f-0a1b2c3d4e5f";
const ORIGINAL = "7d9e8f10-1a2b-4c3d-8e4f-5a6b7c8d9e0f";
const SESSION = "3c9e0d4f-1b2a-4c5d-8e6f-7a8b9c0d1e2f";
const NOW = 1_800_000_000;
const API = "https://api.example";
const PREFIX = `movies/${MOVIE}/${ORIGINAL}`;

interface Call {
  url: string;
  header: string | null;
}

let bucket: FakeBucket;
let env: Env;
let calls: Call[];
let answer: () => Response | Promise<Response>;

function fetcher(input: string, init?: RequestInit): Promise<Response> {
  const headers = new Headers(init?.headers);
  calls.push({ url: input, header: headers.get("X-Velora-Gateway") });
  return Promise.resolve(answer());
}

function live(until = NOW + 3600): Response {
  return Response.json({ live: true, until });
}

beforeEach(() => {
  forgetSessions();
  bucket = new FakeBucket();
  bucket.put(`${PREFIX}/master.m3u8`, "#EXTM3U\n", "application/vnd.apple.mpegurl");
  bucket.put(`${PREFIX}/720p/seg_00000.m4s`, "0123456789", "video/iso.segment");
  env = {
    MEDIA: bucket,
    PLAYBACK_SIGNING_KEY: SECRET,
    ALLOWED_ORIGINS: "http://localhost:8765",
    API_URL: API,
  };
  calls = [];
  answer = () => live();
});

async function sessionGrant(session = SESSION, expires = NOW + 3600) {
  return signGrant(SECRET, { m: MOVIE, o: ORIGINAL, e: expires, s: session });
}

function get(grant: string, file = "master.m3u8", now = NOW) {
  return handle(new Request(`https://media.example/v1/${grant}/${file}`), env, now, fetcher);
}

test("a live session's grant is served, and the API is asked once", async () => {
  const grant = await sessionGrant();
  assert.equal((await get(grant)).status, 200);
  assert.equal((await get(grant, "720p/seg_00000.m4s")).status, 200);
  assert.equal(calls.length, 1, "remembered for a while");
  assert.equal(calls[0].url, `${API}/api/v1/gateway/sessions/${SESSION}`);
});

test("the question is signed as the API checks it", async () => {
  await get(await sessionGrant());
  const key = await importSigningKey(SECRET);
  assert.equal(calls[0].header, await signCheck(key, SESSION, NOW + 60));
});

test("the signature matches the API's, from the shared vector", async () => {
  const vector = JSON.parse(
    readFileSync(new URL("./session-vector.json", import.meta.url), "utf8"),
  );
  const key = await importSigningKey(vector.key);
  assert.equal(await signCheck(key, vector.session_id, vector.check_expires), vector.check);
  const grant = await verifyGrant(key, vector.grant, vector.expires - 1);
  assert.deepEqual(grant, {
    movieId: vector.movie_id,
    originalId: vector.original_id,
    expires: vector.expires,
    sessionId: vector.session_id,
  });
});

test("an ended session's grant is refused, even before it expires", async () => {
  answer = () => Response.json({ live: false, until: null });
  const response = await get(await sessionGrant());
  assert.equal(response.status, 403);
  assert.deepEqual(bucket.requested, []);
});

test("a session ended while playing stops within the fresh period", async () => {
  const grant = await sessionGrant();
  assert.equal((await get(grant)).status, 200);
  answer = () => Response.json({ live: false, until: null });
  assert.equal((await get(grant, "master.m3u8", NOW + 10)).status, 200, "still fresh");
  assert.equal((await get(grant, "master.m3u8", NOW + 31)).status, 403);
});

test("a pass ending stops the session at its end", async () => {
  answer = () => live(NOW + 20);
  const grant = await sessionGrant();
  assert.equal((await get(grant)).status, 200);
  assert.equal((await get(grant, "master.m3u8", NOW + 21)).status, 403);
});

test("an API outage: a session seen live carries on briefly, then 503", async () => {
  const grant = await sessionGrant();
  assert.equal((await get(grant)).status, 200);
  answer = () => new Response("down", { status: 502 });
  assert.equal((await get(grant, "master.m3u8", NOW + 60)).status, 200);
  const late = await get(grant, "master.m3u8", NOW + 200);
  assert.equal(late.status, 503);
  assert.equal(late.headers.get("Retry-After"), "10");
});

test("an unknown session with the API unreachable is never served", async () => {
  answer = () => {
    throw new TypeError("network");
  };
  assert.equal((await get(await sessionGrant())).status, 503);
});

test("a session grant without API_URL isn't served", async () => {
  env.API_URL = undefined;
  assert.equal((await get(await sessionGrant())).status, 503);
  assert.equal(calls.length, 0);
});

test("a grant without a session is served as before, without asking", async () => {
  const grant = await signGrant(SECRET, { m: MOVIE, o: ORIGINAL, e: NOW + 60 });
  assert.equal((await get(grant)).status, 200);
  assert.equal(calls.length, 0);
});

test("a malformed or forged session claim is refused", async () => {
  for (const s of ["not-a-uuid", 12, null, `${SESSION}x`]) {
    const grant = await signGrant(SECRET, { m: MOVIE, o: ORIGINAL, e: NOW + 60, s });
    assert.equal((await get(grant)).status, 403, String(s));
  }
  // Swapping the session in a real grant breaks its signature.
  const real = await sessionGrant();
  const other = await signGrant("another-key-that-is-also-long-enough-0000", {
    m: MOVIE,
    o: ORIGINAL,
    e: NOW + 60,
    s: "11111111-2222-4333-8444-555555555555",
  });
  const forged = `${other.split(".")[0]}.${real.split(".")[1]}`;
  assert.equal((await get(forged)).status, 403);
  assert.equal(calls.length, 0);
});
