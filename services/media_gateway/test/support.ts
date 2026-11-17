// Test helpers: grants signed as the API signs them, and a fake R2 bucket.

import type { R2Bucket, R2Object, R2Range } from "../src/index.ts";

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// The same as services/api/app/playback.py's sign_grant, with any claims.
export function signGrant(secret: string, claims: unknown): Promise<string> {
  return sign(secret, claims, "veloraug-playback-v1.");
}

// The same as services/api/app/playback.py's sign_upload, with any claims.
export function signUploadGrant(secret: string, claims: unknown): Promise<string> {
  return sign(secret, claims, "veloraug-image-v1.");
}

async function sign(secret: string, claims: unknown, context: string): Promise<string> {
  const encoder = new TextEncoder();
  // Python's json.dumps with separators=(",", ":") matches JSON.stringify.
  const payload = toBase64Url(encoder.encode(JSON.stringify(claims)));
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(context + payload),
  );
  return `${payload}.${toBase64Url(new Uint8Array(signature))}`;
}

interface Stored {
  data: Uint8Array;
  contentType: string;
}

// Answers as R2's binding does, for single byte ranges and If-None-Match.
export class FakeBucket implements R2Bucket {
  objects = new Map<string, Stored>();
  requested: string[] = [];

  // As tests fill it, put(key, text, type), or as the Worker writes,
  // put(key, bytes, { httpMetadata }).
  put(
    key: string,
    data: string | Uint8Array | ArrayBuffer,
    type: string | { httpMetadata?: { contentType?: string } } = "video/mp4",
  ): Promise<void> {
    const bytes =
      typeof data === "string"
        ? new TextEncoder().encode(data)
        : data instanceof ArrayBuffer
          ? new Uint8Array(data)
          : data;
    const contentType =
      typeof type === "string" ? type : (type.httpMetadata?.contentType ?? "");
    this.objects.set(key, { data: bytes, contentType });
    this.written.push(key);
    return Promise.resolve();
  }

  written: string[] = [];

  async head(key: string): Promise<R2Object | null> {
    this.requested.push(key);
    const stored = this.objects.get(key);
    return stored ? this.object(key, stored) : null;
  }

  async get(
    key: string,
    options?: { range?: Headers; onlyIf?: Headers },
  ): Promise<R2Object | null> {
    this.requested.push(key);
    const stored = this.objects.get(key);
    if (!stored) return null;
    const object = this.object(key, stored);
    if (options?.onlyIf?.get("If-None-Match") === object.httpEtag) return object;
    const header = options?.range?.get("Range");
    let range: R2Range | undefined;
    let data = stored.data;
    if (header) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(header);
      if (!match) throw new Error("bad range");
      const size = stored.data.length;
      if (match[1] === "") {
        range = { suffix: Number(match[2]) };
        data = data.slice(size - Number(match[2]));
      } else {
        const offset = Number(match[1]);
        if (offset >= size) throw new Error("unsatisfiable");
        const end = match[2] === "" ? size - 1 : Math.min(Number(match[2]), size - 1);
        range = { offset, length: end - offset + 1 };
        data = data.slice(offset, end + 1);
      }
    }
    return {
      ...object,
      range,
      body: new Blob([data]).stream(),
    };
  }

  private object(key: string, stored: Stored): R2Object {
    return {
      size: stored.data.length,
      httpEtag: `"etag-${key.length}-${stored.data.length}"`,
      writeHttpMetadata(headers: Headers) {
        headers.set("Content-Type", stored.contentType);
        // As the media worker publishes: replaced by the gateway.
        headers.set("Cache-Control", "max-age=31536000, immutable");
      },
    };
  }
}
