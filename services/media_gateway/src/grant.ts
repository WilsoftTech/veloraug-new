// Checks playback grants made by the API, in services/api/app/playback.py.
//
// A grant is `<payload>.<signature>`, both base64url without padding. The
// signature is HMAC-SHA256 over GRANT_CONTEXT followed by the payload text.
// The payload is JSON: {"m": movie ID, "o": original ID, "e": expiry, in
// seconds since 1970}. See docs/step-08a-playback-plan.md.
//
// Milestone 10: a grant may also carry "s", a playback session's ID. The
// gateway then asks the API whether that session is still live: see
// src/sessions.ts.

const GRANT_CONTEXT = "veloraug-playback-v1.";
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// Real grants are about 170 characters, 230 with a session. A SHA-256
// signature is 43.
export const GRANT_PATTERN = "[A-Za-z0-9_-]{1,400}\\.[A-Za-z0-9_-]{43}";

export interface Grant {
  movieId: string;
  originalId: string;
  expires: number;
  // The playback session the grant is bound to, if any.
  sessionId?: string;
}

const encoder = new TextEncoder();

function fromBase64Url(text: string): Uint8Array<ArrayBuffer> {
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function importSigningKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    // Sign: the gateway signs its questions to the API about sessions.
    ["verify", "sign"],
  );
}

// The grant, if its signature is right and it hasn't expired. Otherwise
// null: the caller treats every failure the same, so nothing says which.
export async function verifyGrant(
  key: CryptoKey,
  text: string,
  nowSeconds: number,
): Promise<Grant | null> {
  if (!new RegExp(`^${GRANT_PATTERN}$`).test(text)) return null;
  const [payload, signature] = text.split(".");
  let claims: unknown;
  try {
    // crypto.subtle.verify compares in constant time.
    const valid = await crypto.subtle.verify(
      "HMAC",
      key,
      fromBase64Url(signature),
      encoder.encode(GRANT_CONTEXT + payload),
    );
    if (!valid) return null;
    claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payload)));
  } catch {
    return null;
  }
  if (typeof claims !== "object" || claims === null) return null;
  const { m, o, e, s } = claims as Record<string, unknown>;
  if (
    typeof m !== "string" ||
    typeof o !== "string" ||
    !UUID.test(m) ||
    !UUID.test(o) ||
    typeof e !== "number" ||
    !Number.isSafeInteger(e) ||
    (s !== undefined && (typeof s !== "string" || !UUID.test(s)))
  ) {
    return null;
  }
  if (e <= nowSeconds) return null;
  const grant: Grant = { movieId: m, originalId: o, expires: e };
  if (typeof s === "string") grant.sessionId = s;
  return grant;
}
