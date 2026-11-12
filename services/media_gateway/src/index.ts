// The media gateway: serves HLS from private R2 to viewers holding a grant.
//
//   GET /v1/<grant>/master.m3u8
//   GET /v1/<grant>/<quality>/index.m3u8 | init*.mp4 | seg_<n>.m4s
//
// The grant is in the path, so the relative entries in each playlist carry
// it to every file. The R2 path is built from the grant, never from the
// address, so a grant opens one movie's published qualities and nothing
// else: not other movies, and not originals. See
// docs/step-08a-playback-plan.md.
//
// Nothing here logs an address: it contains the grant.

import { GRANT_PATTERN, importSigningKey, verifyGrant } from "./grant.ts";

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
}

export interface Env {
  MEDIA: R2Bucket;
  // Secret, shared with the API. Locally from .dev.vars.
  PLAYBACK_SIGNING_KEY: string;
  // Web app origins allowed to read video, separated by commas.
  ALLOWED_ORIGINS: string;
}

const ROUTE = new RegExp(
  `^/v1/(${GRANT_PATTERN})/(master\\.m3u8|(?:360p|480p|720p|1080p)/` +
    `(?:index\\.m3u8|init(?:_\\d{1,2})?\\.mp4|seg_\\d{1,6}\\.m4s))$`,
);
const MIN_KEY_LENGTH = 32;

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

export async function handle(
  request: Request,
  env: Env,
  nowSeconds: number = Math.floor(Date.now() / 1000),
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

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        ...cors,
        "Access-Control-Allow-Methods": "GET, HEAD",
        "Access-Control-Allow-Headers": "Range",
        "Access-Control-Max-Age": "86400",
      },
    });
  }
  if (request.method !== "GET" && request.method !== "HEAD") {
    return plain(405, "Method not allowed.", { ...cors, Allow: "GET, HEAD" });
  }

  const match = ROUTE.exec(new URL(request.url).pathname);
  if (match === null) return plain(404, "Not found.", cors);

  const secret = env.PLAYBACK_SIGNING_KEY ?? "";
  if (secret.length < MIN_KEY_LENGTH) {
    return plain(503, "Playback isn't set up.", cors);
  }
  const grant = await verifyGrant(await signingKey(secret), match[1], nowSeconds);
  if (grant === null) return plain(403, "Not allowed.", cors);

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

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env);
  },
};
