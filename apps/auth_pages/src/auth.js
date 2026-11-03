import { createAuthClient } from '@neon/auth';
import { BetterAuthReactAdapter } from '@neon/auth/react/adapters';

// credentials goes through the adapter. In @neon/auth 0.8.2 a fetchOptions value
// passed directly to createAuthClient only forwards its headers.
export const authClient = createAuthClient(import.meta.env.VITE_NEON_AUTH_URL, {
  adapter: BetterAuthReactAdapter({ fetchOptions: { credentials: 'include' } }),
});

// With a signed query in the address, the SDK attaches it to each POST and
// navigates by itself when a response has redirect: true.
export function followResponse(data) {
  if (data?.url && !data?.redirect) window.location.assign(data.url);
}

export function hasSignedQuery() {
  return new URLSearchParams(window.location.search).has('sig');
}
