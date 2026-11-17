// Posters and VJ photos that admins upload, Step 9C. See
// docs/step-09a-vj-catalogue-plan.md, decision 15.
//
//   PUT /i/<upload grant>      the image, from an admin's browser
//   GET /i/posters/<...>       public, as are VJ photos under /i/vjs/
//
// An upload grant is made by the API's admin routes, in
// services/api/app/playback.py, like a playback grant but signed for a
// different purpose, so neither can pass for the other. Its payload names
// the one R2 path and image type it allows, and it lasts minutes.

const UPLOAD_CONTEXT = "veloraug-image-v1.";
export const UPLOAD_GRANT_PATTERN = "[A-Za-z0-9_-]{1,400}\\.[A-Za-z0-9_-]{43}";
// posters/<edition ID>/<random>.jpg or vjs/<VJ ID>/<random>.png, and so on.
export const IMAGE_PATH =
  /^(posters|vjs)\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[A-Za-z0-9_-]{16,43}\.(jpg|png|webp)$/;
export const MAX_IMAGE_BYTES = 2_000_000;

const TYPES: Record<string, string> = {
  jpg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
};

export interface UploadGrant {
  path: string;
  type: string;
  expires: number;
}

const encoder = new TextEncoder();

function fromBase64Url(text: string): Uint8Array<ArrayBuffer> {
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function typeFor(path: string): string | undefined {
  return TYPES[path.slice(path.lastIndexOf(".") + 1)];
}

// The grant, if it is signed for uploads, unexpired, and names a path and
// type that go together. Otherwise null, whatever the reason.
export async function verifyUploadGrant(
  key: CryptoKey,
  text: string,
  nowSeconds: number,
): Promise<UploadGrant | null> {
  if (!new RegExp(`^${UPLOAD_GRANT_PATTERN}$`).test(text)) return null;
  const [payload, signature] = text.split(".");
  let claims: unknown;
  try {
    const valid = await crypto.subtle.verify(
      "HMAC",
      key,
      fromBase64Url(signature),
      encoder.encode(UPLOAD_CONTEXT + payload),
    );
    if (!valid) return null;
    claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payload)));
  } catch {
    return null;
  }
  if (typeof claims !== "object" || claims === null) return null;
  const { p, t, e } = claims as Record<string, unknown>;
  if (
    typeof p !== "string" ||
    typeof t !== "string" ||
    !IMAGE_PATH.test(p) ||
    typeFor(p) !== t ||
    typeof e !== "number" ||
    !Number.isSafeInteger(e) ||
    e <= nowSeconds
  ) {
    return null;
  }
  return { path: p, type: t, expires: e };
}

// True if the bytes start as the type says: JPEG, PNG or WebP.
export function looksLike(type: string, bytes: Uint8Array): boolean {
  const starts = (...expected: number[]) =>
    expected.every((value, i) => bytes[i] === value);
  if (type === "image/jpeg") return starts(0xff, 0xd8, 0xff);
  if (type === "image/png") {
    return starts(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a);
  }
  if (type === "image/webp") {
    return (
      starts(0x52, 0x49, 0x46, 0x46) &&
      bytes[8] === 0x57 &&
      bytes[9] === 0x45 &&
      bytes[10] === 0x42 &&
      bytes[11] === 0x50
    );
  }
  return false;
}
