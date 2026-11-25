import { useEffect, useId, useMemo, useRef, useState } from 'react';

import { authClient, followResponse, hasSignedQuery } from './auth.js';
import {
  describeScopes,
  errorMessage,
  isExpiredRequest,
  isLocalAddress,
  isUnverifiedEmail,
  requestHasExpired,
  returnToAppHref,
} from './messages.js';
import { backdropImages } from './backdrop.js';
import { allowedReturnTarget } from './returnTarget.js';

// The sign-in pages Neon Auth redirects to. They never log, and they word every
// failure themselves: see messages.js.

// `onError` may handle a failure itself by returning true.
function useAsyncAction(onExpired, onError) {
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState(null);
  const run = async (action) => {
    setBusy(true);
    setNotice(null);
    try {
      await action((text) => setNotice({ text }));
    } catch (error) {
      if (isExpiredRequest(error)) {
        onExpired?.();
      } else if (!onError?.(error)) {
        setNotice({ text: errorMessage(error), isError: true });
      }
    } finally {
      setBusy(false);
    }
  };
  return { busy, notice, run };
}

function Notice({ notice }) {
  if (!notice) return null;
  return notice.isError ? (
    <p className="notice notice-error" role="alert">
      {notice.text}
    </p>
  ) : (
    <p className="notice" role="status">
      {notice.text}
    </p>
  );
}

function withQuery(path) {
  return `${path}${window.location.search}`;
}

async function continueFlow() {
  const { data, error } = await authClient.oauth2.continue({ selected: true });
  if (error) throw error;
  followResponse(data);
}

// A field whose label sits inside it and floats up once there is something in
// it. The placeholder is a single space so CSS can tell when it's empty. The
// hint under it shows only once the browser finds the value invalid, after
// the person has interacted with it, and the field names it for screen
// readers.
function Field({ label, error, children, toggle }) {
  const id = useId();
  const hintId = `${id}-hint`;
  return (
    <div className={toggle ? 'field field-with-toggle' : 'field'}>
      {children({ id, placeholder: ' ', 'aria-describedby': hintId })}
      <label htmlFor={id}>{label}</label>
      {toggle}
      <p className="field-hint" id={hintId}>
        {error}
      </p>
    </div>
  );
}

function EmailField({ value, onChange }) {
  return (
    <Field label="Email" error="Enter an email address, like name@example.com.">
      {(props) => (
        <input
          {...props}
          type="email"
          autoComplete="username"
          required
          value={value}
          onChange={(event) => onChange(event.target.value)}
        />
      )}
    </Field>
  );
}

function EyeIcon({ crossed }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M12 5C6.5 5 2.7 9.2 1.5 12c1.2 2.8 5 7 10.5 7s9.3-4.2 10.5-7C21.3 9.2 17.5 5 12 5Zm0 11.5a4.5 4.5 0 1 1 0-9 4.5 4.5 0 0 1 0 9Zm0-2.5a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z" />
      {crossed && <path d="M3.3 2 22 20.7 20.7 22 2 3.3Z" />}
    </svg>
  );
}

// Show password is a toggle: screen readers hear its name and whether it's on.
function PasswordField({ label, autoComplete, value, onChange }) {
  const [shown, setShown] = useState(false);
  return (
    <Field
      label={label}
      error="Enter a password."
      toggle={
        <button
          type="button"
          className="field-toggle"
          aria-label="Show password"
          aria-pressed={shown}
          title={shown ? 'Hide password' : 'Show password'}
          onClick={() => setShown((now) => !now)}
        >
          <EyeIcon crossed={shown} />
        </button>
      }
    >
      {(props) => (
        <input
          {...props}
          type={shown ? 'text' : 'password'}
          autoComplete={autoComplete}
          required
          value={value}
          onChange={(event) => onChange(event.target.value)}
        />
      )}
    </Field>
  );
}

function CodeField({ value, onChange }) {
  return (
    <Field label="Code from your email" error="Enter the code from your email.">
      {(props) => (
        <input
          {...props}
          inputMode="numeric"
          autoComplete="one-time-code"
          required
          value={value}
          onChange={(event) => onChange(event.target.value)}
        />
      )}
    </Field>
  );
}

// The server answers a sign-up for an existing address as if it were new, so this
// page says the same for both and doesn't reveal which it was.
function VerifyEmailForm({ email, sendOnLoad, onExpired }) {
  const [code, setCode] = useState('');
  const { busy, notice, run } = useAsyncAction(onExpired);
  const sent = useRef(false);

  const sendCode = () =>
    run(async (show) => {
      const { error } = await authClient.emailOtp.sendVerificationOtp({
        email,
        type: 'email-verification',
      });
      if (error) throw error;
      show('We sent a new code. Check your email.');
    });

  useEffect(() => {
    if (!sendOnLoad || sent.current) return;
    sent.current = true;
    sendCode();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sendOnLoad]);

  const verify = (event) => {
    event.preventDefault();
    run(async () => {
      const { data, error } = await authClient.emailOtp.verifyEmail({
        email,
        otp: code,
      });
      if (error) throw error;
      if (data?.url) {
        followResponse(data);
      } else if (data?.session || data?.token) {
        await continueFlow();
      } else {
        window.location.assign(withQuery('/login'));
      }
    });
  };

  return (
    <>
      <h1>Enter your code</h1>
      <p>We sent a code to {email}. It lasts about 15 minutes.</p>
      <form onSubmit={verify}>
        <CodeField value={code} onChange={setCode} />
        <button disabled={busy}>Verify</button>
      </form>
      <Notice notice={notice} />
      <div className="actions">
        <button
          type="button"
          className="button-quiet"
          disabled={busy}
          onClick={sendCode}
        >
          Send a new code
        </button>
      </div>
      <p>
        Already have an account with this address?{' '}
        <a href={withQuery('/login')}>Sign in</a> or{' '}
        <a href={withQuery('/reset')}>reset your password</a>.
      </p>
    </>
  );
}

function LoginPage({ onExpired }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [unverified, setUnverified] = useState(false);
  const { busy, notice, run } = useAsyncAction(onExpired, (error) => {
    if (!isUnverifiedEmail(error)) return false;
    setUnverified(true);
    return true;
  });
  const signedQuery = hasSignedQuery();
  const checked = useRef(false);

  useEffect(() => {
    if (!signedQuery || checked.current) return;
    checked.current = true;
    run(async () => {
      const { data } = await authClient.getSession();
      if (data?.user) await continueFlow();
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [signedQuery]);

  if (!signedQuery) {
    return <p>Start signing in from the VeloraUG app.</p>;
  }

  if (unverified) {
    return <VerifyEmailForm email={email} sendOnLoad onExpired={onExpired} />;
  }

  const submit = (event) => {
    event.preventDefault();
    run(async () => {
      const { data, error } = await authClient.signIn.email({ email, password });
      if (error) throw error;
      followResponse(data);
    });
  };

  return (
    <>
      <h1>Sign in</h1>
      <form onSubmit={submit}>
        <EmailField value={email} onChange={setEmail} />
        <PasswordField
          label="Password"
          autoComplete="current-password"
          value={password}
          onChange={setPassword}
        />
        <button disabled={busy}>Sign in</button>
      </form>
      <Notice notice={notice} />
      <p>
        <a href={withQuery('/sign-up')}>Create an account</a>
      </p>
      <p>
        <a href={withQuery('/reset')}>Forgot password</a>
      </p>
    </>
  );
}

function SignUpPage({ onExpired }) {
  const [displayName, setDisplayName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [awaitingCode, setAwaitingCode] = useState(false);
  const { busy, notice, run } = useAsyncAction(onExpired);

  const signUp = (event) => {
    event.preventDefault();
    run(async () => {
      const { data, error } = await authClient.signUp.email({
        email,
        password,
        name: displayName,
      });
      if (error) throw error;
      if (data?.user?.emailVerified === false) {
        setAwaitingCode(true);
      } else {
        await continueFlow();
      }
    });
  };

  if (awaitingCode) {
    return <VerifyEmailForm email={email} onExpired={onExpired} />;
  }

  return (
    <>
      <h1>Create an account</h1>
      <form onSubmit={signUp}>
        <Field label="Display name" error="Enter a display name.">
          {(props) => (
            <input
              {...props}
              autoComplete="name"
              required
              maxLength={80}
              value={displayName}
              onChange={(event) => setDisplayName(event.target.value)}
            />
          )}
        </Field>
        <EmailField value={email} onChange={setEmail} />
        <PasswordField
          label="Password, at least 8 characters"
          autoComplete="new-password"
          value={password}
          onChange={setPassword}
        />
        <button disabled={busy}>Create account</button>
      </form>
      <Notice notice={notice} />
      <p>
        <a href={withQuery('/login')}>Back to sign in</a>
      </p>
    </>
  );
}

// The wording is the same whether or not the address has an account.
function ResetPage({ onExpired }) {
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [password, setPassword] = useState('');
  const [step, setStep] = useState('request');
  const { busy, notice, run } = useAsyncAction(onExpired);

  const sendCode = (text) =>
    run(async (show) => {
      const { error } = await authClient.forgetPassword.emailOtp({ email });
      if (error) throw error;
      setStep('enter-code');
      show(text);
    });

  const request = (event) => {
    event.preventDefault();
    sendCode('If that address has an account, we sent it a code.');
  };

  const reset = (event) => {
    event.preventDefault();
    run(async () => {
      const { error } = await authClient.emailOtp.resetPassword({
        email,
        otp: code,
        password,
      });
      if (error) throw error;
      setStep('done');
    });
  };

  if (step === 'done') {
    return (
      <>
        <h1>Password changed</h1>
        <p>Sign in with your new password.</p>
        <a className="button" href={withQuery('/login')}>
          Sign in
        </a>
      </>
    );
  }

  if (step === 'enter-code') {
    return (
      <>
        <h1>Choose a new password</h1>
        <form onSubmit={reset}>
          <CodeField value={code} onChange={setCode} />
          <PasswordField
            label="New password, at least 8 characters"
            autoComplete="new-password"
            value={password}
            onChange={setPassword}
          />
          <button disabled={busy}>Change password</button>
        </form>
        <Notice notice={notice} />
        <div className="actions">
          <button
            type="button"
            className="button-quiet"
            disabled={busy}
            onClick={() => sendCode('If that address has an account, we sent it a new code.')}
          >
            Send a new code
          </button>
        </div>
        <p>
          <a href={withQuery('/login')}>Back to sign in</a>
        </p>
      </>
    );
  }

  return (
    <>
      <h1>Forgot password</h1>
      <form onSubmit={request}>
        <EmailField value={email} onChange={setEmail} />
        <button disabled={busy}>Send reset code</button>
      </form>
      <Notice notice={notice} />
      <p>
        <a href={withQuery('/login')}>Back to sign in</a>
      </p>
    </>
  );
}

function ConsentPage({ onExpired }) {
  const params = useMemo(() => new URLSearchParams(window.location.search), []);
  const [clientName, setClientName] = useState(null);
  const { busy, notice, run } = useAsyncAction(onExpired);
  const clientId = params.get('client_id');
  const redirectUri = params.get('redirect_uri');
  const loaded = useRef(false);

  useEffect(() => {
    if (!clientId || loaded.current) return;
    loaded.current = true;
    run(async () => {
      const { data, error } = await authClient.oauth2.publicClient({
        query: { client_id: clientId },
      });
      if (error) throw error;
      setClientName(data?.client_name ?? null);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clientId]);

  const respond = (accept) =>
    run(async () => {
      const { data, error } = await authClient.oauth2.consent({ accept });
      if (error) throw error;
      followResponse(data);
    });

  let callbackHost = 'Unknown';
  try {
    callbackHost = new URL(redirectUri).host;
  } catch {
    // Shown as unknown.
  }
  const scopes = describeScopes(params.get('scope'));

  return (
    <>
      <h1>Allow access?</h1>
      <dl>
        <dt>App</dt>
        <dd>{clientName ?? clientId ?? 'Unknown'}</dd>
        <dt>Returns to</dt>
        <dd>{callbackHost}</dd>
        <dt>It will be able to</dt>
        {scopes.length ? (
          scopes.map((scope) => <dd key={scope}>{scope}</dd>)
        ) : (
          <dd>Unknown</dd>
        )}
        <dt>For</dt>
        <dd>{params.get('resource') ?? 'Unknown'}</dd>
      </dl>
      {isLocalAddress(callbackHost) && (
        <p className="notice notice-error" role="alert">
          This app runs on this computer. Allow it only if you started it
          yourself.
        </p>
      )}
      <div className="actions">
        <button disabled={busy} onClick={() => respond(true)}>
          Allow
        </button>
        <button disabled={busy} onClick={() => respond(false)}>
          Deny
        </button>
      </div>
      <Notice notice={notice} />
    </>
  );
}

function SignOutPage() {
  const { busy, notice, run } = useAsyncAction();
  const target = allowedReturnTarget(
    new URLSearchParams(window.location.search).get('return'),
    window.location.origin,
  );

  const signOut = () =>
    run(async (show) => {
      const { error } = await authClient.signOut();
      if (error) throw error;
      if (target) {
        window.location.assign(`${target}?signed_out=1`);
      } else {
        show('Signed out. You can close this page.');
      }
    });

  return (
    <>
      <h1>Sign out</h1>
      <p>This signs you out of VeloraUG in this browser.</p>
      <button disabled={busy} onClick={signOut}>
        Sign out
      </button>
      <Notice notice={notice} />
    </>
  );
}

// Android normally opens the app for this address without showing the page. If
// it appears, the button gives Android a tap to act on.
function AndroidCallbackPage() {
  const [returnHref] = useState(() => window.location.href);

  useEffect(() => {
    window.history.replaceState(null, '', window.location.pathname);
  }, []);

  return (
    <>
      <h1>Return to VeloraUG</h1>
      <p>
        If the app did not open by itself, tap the button. This address must be
        opened on the phone that started signing in.
      </p>
      <a className="button" href={returnHref}>
        Open VeloraUG
      </a>
    </>
  );
}

// Neon's signed request lasts about 10 minutes, and every call fails once it ends,
// even with a correct password or code. A new one can only come from the app.
function ExpiredRequestPage() {
  const href = returnToAppHref(window.location.search, window.location.origin);
  return (
    <>
      <h1>This sign-in has timed out</h1>
      <p>
        Sign-in requests last about 10 minutes. Go back to the app and sign in
        again. If you already created an account, sign in with it, and you can
        confirm your email from there.
      </p>
      {href ? (
        <a className="button" href={href}>
          Back to VeloraUG
        </a>
      ) : (
        <p>You can close this page.</p>
      )}
    </>
  );
}

const signedPages = {
  '/login': LoginPage,
  '/sign-up': SignUpPage,
  '/reset': ResetPage,
  '/consent': ConsentPage,
};

const otherPages = {
  '/sign-out': SignOutPage,
  '/auth/callback/android': AndroidCallbackPage,
};

function currentSeconds() {
  return Math.floor(Date.now() / 1000);
}

export function App() {
  const path = window.location.pathname;
  const [expired, setExpired] = useState(() =>
    requestHasExpired(window.location.search, currentSeconds()),
  );
  const SignedPage = signedPages[path];
  const OtherPage = otherPages[path];

  let page = <p>Open this site from the VeloraUG app.</p>;
  if (SignedPage && expired) {
    page = <ExpiredRequestPage />;
  } else if (SignedPage) {
    page = <SignedPage onExpired={() => setExpired(true)} />;
  } else if (OtherPage) {
    page = <OtherPage />;
  }

  return (
    <>
      <Backdrop />
      <div className="layout">
        <div className="card">
          <header className="brand">
            <img
              className="brand-mark"
              src="/brand/velora-mark-48.png"
              srcSet="/brand/velora-mark-48.png 1x, /brand/velora-mark-96.png 2x"
              alt=""
            />
            <span>
              Velora<span className="brand-suffix">UG</span>
            </span>
          </header>
          <main>{page}</main>
        </div>
        <footer className="footer">
          VeloraUG · Movies and series translated into Luganda by Uganda&apos;s
          VJs
        </footer>
      </div>
    </>
  );
}

// How many tiles the collage has. Pictures repeat to fill it.
const BACKDROP_TILES = 24;

// A still collage of posters behind the card, darkened towards the page's
// colour so the card always reads. Without pictures, tiles in the brand's
// colours stand in. It's decoration, so screen readers skip it.
function Backdrop() {
  return (
    <div className="backdrop" aria-hidden="true">
      <div className="backdrop-tiles">
        {Array.from({ length: BACKDROP_TILES }, (_, i) =>
          backdropImages.length ? (
            <img
              key={i}
              className="backdrop-tile"
              src={backdropImages[i % backdropImages.length]}
              alt=""
              loading="lazy"
              decoding="async"
            />
          ) : (
            <span key={i} className={`backdrop-tile backdrop-tile-${i % 4}`} />
          ),
        )}
      </div>
    </div>
  );
}
