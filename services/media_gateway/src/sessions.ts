// Milestone 10: is a grant's playback session still live?
//
// A grant bound to a session ("s") is only honoured while the API says the
// session is live: its device is still registered, it hasn't been stopped
// or replaced, the player has said it's still watching within the last
// three minutes, and its pass is running. So removing a device, stopping a
// session, a reversed payment or an expired pass stops the video within
// FRESH_SECONDS, long before the grant itself runs out.
//
// The question is signed with the shared playback key under its own
// context, so only this gateway can ask, and it names the session alone:
// nothing about the viewer travels either way.
//
//   GET <API_URL>/api/v1/gateway/sessions/<session>
//   X-Velora-Gateway: <expires>.<HMAC-SHA256("veloraug-gateway-v1." + session + "." + expires)>
//
// Answers are kept in this isolate's memory for FRESH_SECONDS. If the API
// can't be reached, a session seen live within GRACE_SECONDS carries on, so
// a moment's outage doesn't stop everyone's film; otherwise the gateway
// answers 503 and refuses to serve.

const GATEWAY_CONTEXT = "veloraug-gateway-v1.";
export const FRESH_SECONDS = 30;
export const GRACE_SECONDS = 120;
const SIGNATURE_SECONDS = 60;
const TIMEOUT_MS = 4000;
const MAX_ENTRIES = 5000;

export type SessionState = "live" | "ended" | "unknown";
export type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;

interface Seen {
  live: boolean;
  until: number | null;
  checked: number;
  lastLive: number | null;
}

const seen = new Map<string, Seen>();
const encoder = new TextEncoder();

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function signCheck(
  key: CryptoKey,
  sessionId: string,
  expires: number,
): Promise<string> {
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`${GATEWAY_CONTEXT}${sessionId}.${expires}`),
  );
  return `${expires}.${toBase64Url(new Uint8Array(signature))}`;
}

// For tests: start with nothing remembered.
export function forgetSessions(): void {
  seen.clear();
}

function remember(sessionId: string, entry: Seen): void {
  if (seen.size >= MAX_ENTRIES) seen.clear();
  seen.set(sessionId, entry);
}

function judge(entry: Seen, now: number): SessionState {
  if (!entry.live) return "ended";
  if (entry.until !== null && entry.until <= now) return "ended";
  return "live";
}

export async function sessionState(
  key: CryptoKey,
  apiUrl: string,
  sessionId: string,
  now: number,
  fetcher: Fetcher,
): Promise<SessionState> {
  const known = seen.get(sessionId);
  if (known !== undefined && now - known.checked < FRESH_SECONDS) {
    return judge(known, now);
  }
  const base = apiUrl.replace(/\/+$/, "");
  let answer: { live?: unknown; until?: unknown } | null = null;
  try {
    const response = await fetcher(`${base}/api/v1/gateway/sessions/${sessionId}`, {
      headers: {
        "X-Velora-Gateway": await signCheck(key, sessionId, now + SIGNATURE_SECONDS),
        Accept: "application/json",
      },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (response.status === 200) {
      answer = (await response.json()) as { live?: unknown; until?: unknown };
    }
  } catch {
    answer = null;
  }
  if (answer === null || typeof answer.live !== "boolean") {
    // The API couldn't say. A session seen live lately carries on.
    if (known?.lastLive != null && now - known.lastLive < GRACE_SECONDS) {
      return judge({ ...known, live: true }, now);
    }
    return "unknown";
  }
  const until =
    typeof answer.until === "number" && Number.isSafeInteger(answer.until)
      ? answer.until
      : null;
  const entry: Seen = {
    live: answer.live,
    until,
    checked: now,
    lastLive: answer.live ? now : (known?.lastLive ?? null),
  };
  // An ended session never comes back, so a "no" is final.
  if (!answer.live) entry.lastLive = null;
  remember(sessionId, entry);
  return judge(entry, now);
}
