// The only places the sign-out page may send a browser back to. Anything else
// is refused, so the page cannot be used to redirect people to another site.
export function allowedReturnTarget(value, pageOrigin) {
  const allowed = [
    'http://localhost:8765/auth.html',
    `${pageOrigin}/auth/callback/android`,
  ];
  return allowed.includes(value) ? value : null;
}
