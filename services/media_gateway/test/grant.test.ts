import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { importSigningKey, verifyGrant } from "../src/grant.ts";
import { signGrant } from "./support.ts";

const vector = JSON.parse(
  readFileSync(new URL("./grant-vector.json", import.meta.url), "utf8"),
);

test("the grant the API's tests make is accepted", async () => {
  // The same vector is checked in services/api/tests/test_playback.py.
  const key = await importSigningKey(vector.key);
  const grant = await verifyGrant(key, vector.grant, vector.expires - 1);
  assert.deepEqual(grant, {
    movieId: vector.movie_id,
    originalId: vector.original_id,
    expires: vector.expires,
    purpose: "playback",
  });
  const download = await verifyGrant(key, vector.download_grant, vector.expires - 1);
  assert.equal(download?.purpose, "download");
});

test("signing here gives the API's exact grant", async () => {
  const grant = await signGrant(vector.key, {
    m: vector.movie_id,
    o: vector.original_id,
    e: vector.expires,
    p: "playback",
  });
  assert.equal(grant, vector.grant);
});

test("an expired grant is refused, at the second it expires", async () => {
  const key = await importSigningKey(vector.key);
  assert.equal(await verifyGrant(key, vector.grant, vector.expires), null);
  assert.equal(await verifyGrant(key, vector.grant, vector.expires + 60), null);
});

test("another key's grant is refused", async () => {
  const key = await importSigningKey("another-key-of-plenty-of-length-0123456789");
  assert.equal(await verifyGrant(key, vector.grant, 0), null);
});

test("a changed payload or signature is refused", async () => {
  const key = await importSigningKey(vector.key);
  const [payload, signature] = vector.grant.split(".");
  const other = await signGrant("x".repeat(40), {
    m: vector.movie_id,
    o: vector.movie_id,
    e: vector.expires,
  });
  const flipped = signature.slice(0, -2) + (signature.at(-2) === "A" ? "B" : "A") + signature.at(-1);
  for (const text of [
    `${other.split(".")[0]}.${signature}`,
    `${payload}.${flipped}`,
    `${payload}x.${signature}`,
    payload,
    `${payload}.${signature}.extra`,
    "",
    `${payload}.${signature}`.replace("e", "%"),
  ]) {
    assert.equal(await verifyGrant(key, text, 0), null, text);
  }
});

test("a well-signed grant with bad contents is refused", async () => {
  const secret = "s".repeat(40);
  const key = await importSigningKey(secret);
  const good = { m: vector.movie_id, o: vector.original_id, e: 2_000_000_000, p: "playback" };
  const session = "3c9e0d4f-1b2a-4c5d-8e6f-7a8b9c0d1e2f";
  for (const claims of [
    { ...good, m: "../../originals" },
    { ...good, o: vector.original_id.toUpperCase() },
    { ...good, e: "2000000000" },
    { ...good, e: 1.5 },
    { m: good.m, o: good.o, e: good.e },
    { ...good, p: "stream" },
    { ...good, p: "" },
    { ...good, p: ["download"] },
    // Only playback is bound to a session: a download or preview never is.
    { ...good, p: "download", s: session },
    { ...good, p: "preview", s: session },
    { m: good.m, o: good.o },
    [],
    "text",
  ]) {
    const grant = await signGrant(secret, claims);
    assert.equal(await verifyGrant(key, grant, 0), null, JSON.stringify(claims));
  }
  assert.notEqual(await verifyGrant(key, await signGrant(secret, good), 0), null);
});
