// The media gateway: serves HLS from private R2 to viewers holding a grant.
//
//   GET /v1/<grant>/master.m3u8
//   GET /v1/<grant>/<quality>/index.m3u8 | init*.mp4 | seg_<n>.m4s
//   GET /v1/<grant>/<quality>/download.mp4?name=<file name>
//
//   PUT /i/<upload grant>, GET /i/posters/..., GET /i/vjs/...
//
// The last are admins' uploaded images, from Step 9C: see src/images.ts.
//
// download.mp4, from Step 12A, is a quality's whole video as one file, for
// viewers to download and keep. It is sent as an attachment named by
// ?name=, so a browser saves it to disk rather than playing it.
//
// The grant is in the path, so the relative entries in each playlist carry
// it to every file. The R2 path is built from the grant, never from the
// address, so a grant opens one movie's published qualities and nothing
// else: not other movies, and not originals. See
// docs/step-08a-playback-plan.md.
//
// Nothing here logs an address: it contains the grant.

import { GRANT_PATTERN, importSigningKey, verifyGrant } from "./grant.ts";
import { type Fetcher, sessionState } from "./sessions.ts";
import {
  IMAGE_PATH,
  MAX_IMAGE_BYTES,
  UPLOAD_GRANT_PATTERN,
  looksLike,
  typeFor,
  verifyUploadGrant,
} from "./images.ts";

// Only the parts of the R2 binding used here.
export interface R2Range {
  offset?: number;
  length?: number;
  suffix?: number;
}
export interface R2Object {
  size: number;
  httpEtag: string;
  range?: R2Range;
  body?: ReadableStream;
  writeHttpMetadata(headers: Headers): void;
}
export interface R2Bucket {
  get(
    key: string,
    options?: { range?: Headers; onlyIf?: Headers },
  ): Promise<R2Object | null>;
  head(key: string): Promise<R2Object | null>;
  put(
    key: string,
    value: ArrayBuffer,
    options?: { httpMetadata?: { contentType?: string; cacheControl?: string } },
  ): Promise<unknown>;
}

export interface Env {
  MEDIA: R2Bucket;
  // Secret, shared with the API. Locally from .dev.vars.
  PLAYBACK_SIGNING_KEY: string;
  // Web app origins allowed to read video, separated by commas.
  ALLOWED_ORIGINS: string;
  // The API's origin, which says whether a grant's playback session is
  // still live (Milestone 10). Without it, a session-bound grant gets 503.
  API_URL?: string;
}

const ROUTE = new RegExp(
  `^/v1/(${GRANT_PATTERN})/(master\\.m3u8|(?:360p|480p|720p|1080p)/` +
    `(?:index\\.m3u8|init(?:_\\d{1,2})?\\.mp4|seg_\\d{1,6}\\.m4s|download\\.mp4))$`,
);
const MIN_KEY_LENGTH = 32;
const UPLOAD_ROUTE = new RegExp(`^/i/(${UPLOAD_GRANT_PATTERN})$`);
const IMAGE_ROUTE = /^\/i\/(.+)$/;

let cachedKey: { secret: string; key: Promise<CryptoKey> } | undefined;

function signingKey(secret: string): Promise<CryptoKey> {
  if (cachedKey?.secret !== secret) {
    cachedKey = { secret, key: importSigningKey(secret) };
  }
  return cachedKey.key;
}

function plain(status: number, text: string, headers?: HeadersInit): Response {
  const response = new Response(text + "\n", { status, headers });
  response.headers.set("Content-Type", "text/plain; charset=utf-8");
  response.headers.set("Cache-Control", "no-store");
  return response;
}

function corsHeaders(origin: string | null): Record<string, string> {
  if (origin === null) return {};
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Expose-Headers": "Content-Length, Content-Range, ETag",
    Vary: "Origin",
  };
}

function contentRange(range: R2Range, size: number): [number, number] {
  if (range.suffix !== undefined) {
    return [Math.max(0, size - range.suffix), size - 1];
  }
  const start = range.offset ?? 0;
  const length = range.length ?? size - start;
  return [start, Math.min(size, start + length) - 1];
}

// "attachment; filename=..." with a name that is safe everywhere: letters,
// digits, spaces and . , ' ( ) - only, ending in .mp4.
export function attachment(name: string | null, quality: string): string {
  let safe = (name ?? "")
    .replace(/[^A-Za-z0-9 .,'()-]+/g, " ")
    .replace(/\s+/g, " ")
    .replace(/^[ .-]+/, "")
    .slice(0, 120)
    .trim();
  if (!safe.toLowerCase().endsWith(".mp4")) {
    safe = `${safe.replace(/[ .-]+$/, "") || "VeloraUG"} - ${quality}.mp4`;
  }
  return `attachment; filename="${safe}"`;
}

export async function handle(
  request: Request,
  env: Env,
  nowSeconds: number = Math.floor(Date.now() / 1000),
  fetcher: Fetcher = (input, init) => fetch(input, init),
): Promise<Response> {
  const origin = request.headers.get("Origin");
  if (origin !== null) {
    const allowed = (env.ALLOWED_ORIGINS ?? "")
      .split(",")
      .map((o) => o.trim())
      .filter(Boolean);
    if (!allowed.includes(origin)) return plain(403, "Not allowed.");
  }
  const cors = corsHeaders(origin);

  const pathname = new URL(request.url).pathname;
  const isImage = pathname.startsWith("/i/");

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        ...cors,
        "Access-Control-Allow-Methods": isImage ? "GET, HEAD, PUT" : "GET, HEAD",
        "Access-Control-Allow-Headers": isImage ? "Content-Type" : "Range",
        "Access-Control-Max-Age": "86400",
      },
    });
  }
  const methods = isImage ? ["GET", "HEAD", "PUT"] : ["GET", "HEAD"];
  if (!methods.includes(request.method)) {
    return plain(405, "Method not allowed.", { ...cors, Allow: methods.join(", ") });
  }

  const secret = env.PLAYBACK_SIGNING_KEY ?? "";
  if (isImage) return images(request, env, pathname, secret, cors, nowSeconds);

  const match = ROUTE.exec(pathname);
  if (match === null) return plain(404, "Not found.", cors);

  if (secret.length < MIN_KEY_LENGTH) {
    return plain(503, "Playback isn't set up.", cors);
  }
  const signing = await signingKey(secret);
  const grant = await verifyGrant(signing, match[1], nowSeconds);
  const download = match[2].endsWith("/download.mp4");
  if (grant === null || (grant.purpose === "download") !== download) {
    return plain(403, "Not allowed.", cors);
  }
  if (grant.sessionId !== undefined) {
    // Milestone 10: honoured only while its session is live.
    const apiUrl = env.API_URL ?? "";
    if (!/^https?:\/\//.test(apiUrl)) {
      return plain(503, "Playback isn't set up.", cors);
    }
    const state = await sessionState(signing, apiUrl, grant.sessionId, nowSeconds, fetcher);
    if (state === "ended") return plain(403, "Not allowed.", cors);
    if (state === "unknown") {
      return plain(503, "Playback can't be checked right now.", {
        ...cors,
        "Retry-After": "10",
      });
    }
  }

  const key = `movies/${grant.movieId}/${grant.originalId}/${match[2]}`;
  let object: R2Object | null;
  try {
    object =
      request.method === "HEAD"
        ? await env.MEDIA.head(key)
        : await env.MEDIA.get(key, {
            range: request.headers,
            onlyIf: request.headers,
          });
  } catch {
    // R2 refuses a range it can't satisfy.
    return plain(416, "Range not satisfiable.", cors);
  }
  if (object === null) return plain(404, "Not found.", cors);

  const headers = new Headers(cors);
  object.writeHttpMetadata(headers);
  headers.set("ETag", object.httpEtag);
  headers.set("Accept-Ranges", "bytes");
  // Per viewer: the address holds their grant. Shared caches mustn't keep it.
  headers.set("Cache-Control", "private, max-age=3600");
  headers.set("X-Content-Type-Options", "nosniff");
  if (match[2].endsWith("/download.mp4")) {
    const quality = match[2].split("/")[0];
    const name = new URL(request.url).searchParams.get("name");
    headers.set("Content-Disposition", attachment(name, quality));
  }

  if (request.method === "HEAD") {
    headers.set("Content-Length", String(object.size));
    return new Response(null, { status: 200, headers });
  }
  if (object.body === undefined) {
    // A condition in the request failed.
    const notModified =
      request.headers.has("If-None-Match") ||
      request.headers.has("If-Modified-Since");
    return new Response(null, { status: notModified ? 304 : 412, headers });
  }
  if (request.headers.has("Range") && object.range !== undefined) {
    const [start, end] = contentRange(object.range, object.size);
    headers.set("Content-Range", `bytes ${start}-${end}/${object.size}`);
    headers.set("Content-Length", String(end - start + 1));
    return new Response(object.body, { status: 206, headers });
  }
  headers.set("Content-Length", String(object.size));
  return new Response(object.body, { status: 200, headers });
}

async function images(
  request: Request,
  env: Env,
  pathname: string,
  secret: string,
  cors: Record<string, string>,
  nowSeconds: number,
): Promise<Response> {
  if (request.method === "PUT") {
    const match = UPLOAD_ROUTE.exec(pathname);
    if (match === null) return plain(404, "Not found.", cors);
    if (secret.length < MIN_KEY_LENGTH) {
      return plain(503, "Uploads aren't set up.", cors);
    }
    const grant = await verifyUploadGrant(
      await signingKey(secret),
      match[1],
      nowSeconds,
    );
    if (grant === null) return plain(403, "Not allowed.", cors);
    if (request.headers.get("Content-Type") !== grant.type) {
      return plain(415, "That isn't the image type this upload was for.", cors);
    }
    const declared = Number(request.headers.get("Content-Length") ?? "0");
    if (declared > MAX_IMAGE_BYTES) {
      return plain(413, "Images can be at most 2 MB.", cors);
    }
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (bytes.length > MAX_IMAGE_BYTES) {
      return plain(413, "Images can be at most 2 MB.", cors);
    }
    if (!looksLike(grant.type, bytes)) {
      return plain(415, "That file isn't the image it says it is.", cors);
    }
    await env.MEDIA.put(grant.path, bytes.buffer, {
      httpMetadata: {
        contentType: grant.type,
        // The path has a random part, so it never changes.
        cacheControl: "public, max-age=31536000, immutable",
      },
    });
    const headers = { ...cors, "Content-Type": "application/json" };
    return new Response(JSON.stringify({ path: grant.path }), {
      status: 201,
      headers,
    });
  }

  const match = IMAGE_ROUTE.exec(pathname);
  const path = match?.[1] ?? "";
  if (!IMAGE_PATH.test(path)) return plain(404, "Not found.", cors);
  const object =
    request.method === "HEAD"
      ? await env.MEDIA.head(path)
      : await env.MEDIA.get(path, { onlyIf: request.headers });
  if (object === null) return plain(404, "Not found.", cors);
  const headers = new Headers(cors);
  headers.set("Content-Type", typeFor(path) ?? "application/octet-stream");
  headers.set("ETag", object.httpEtag);
  headers.set("Cache-Control", "public, max-age=31536000, immutable");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Content-Length", String(object.size));
  if (request.method === "HEAD") return new Response(null, { status: 200, headers });
  if (object.body === undefined) return new Response(null, { status: 304, headers });
  return new Response(object.body, { status: 200, headers });
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env);
  },
};
