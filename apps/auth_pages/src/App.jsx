import { useEffect, useMemo, useRef, useState } from 'react';

import { authClient, followResponse, hasSignedQuery } from './auth.js';
import { allowedReturnTarget } from './returnTarget.js';

// A minimal companion for testing the Step 5B gates, not the finished pages.
// It never logs. It shows only Neon's own error code and message.

function errorText(error) {
  if (!error) return 'The request failed.';
  return [error.code, error.message].filter(Boolean).join(': ');
}

function useAsyncAction() {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);
  const run = async (action) => {
    setBusy(true);
    setMessage(null);
    try {
      await action(setMessage);
    } catch (error) {
      setMessage(errorText(error));
    } finally {
      setBusy(false);
    }
  };
  return { busy, message, run };
}

function Notice({ children }) {
  return children ? (
    <p className="notice" role="status">
      {children}
    </p>
  ) : null;
}

function withQuery(path) {
  return `${path}${window.location.search}`;
}

async function continueFlow() {
  const { data, error } = await authClient.oauth2.continue({ selected: true });
  if (error) throw error;
  followResponse(data);
}

function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const { busy, message, run } = useAsyncAction();
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
    return (
      <p>
        Start signing in from the VeloraUG app. This page needs the request the
        app sends.
      </p>
    );
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
        <label>
          Email
          <input
            type="email"
            autoComplete="username"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
        </label>
        <label>
          Password
          <input
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
        </label>
        <button disabled={busy}>Sign in</button>
      </form>
      <Notice>{message}</Notice>
      <p>
        <a href={withQuery('/sign-up')}>Create an account</a>
      </p>
      <p>
        <a href={withQuery('/reset')}>Forgot password</a>
      </p>
    </>
  );
}

function SignUpPage() {
  const [displayName, setDisplayName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [awaitingCode, setAwaitingCode] = useState(false);
  const { busy, message, run } = useAsyncAction();

  const signUp = (event) => {
    event.preventDefault();
    run(async (show) => {
      const { data, error } = await authClient.signUp.email({
        email,
        password,
        name: displayName,
      });
      if (error) throw error;
      if (data?.user?.emailVerified === false) {
        setAwaitingCode(true);
        show('Check your email for a code.');
      } else {
        await continueFlow();
      }
    });
  };

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

  if (awaitingCode) {
    return (
      <>
        <h1>Enter your code</h1>
        <form onSubmit={verify}>
          <label>
            Code from your email
            <input
              inputMode="numeric"
              autoComplete="one-time-code"
              required
              value={code}
              onChange={(event) => setCode(event.target.value)}
            />
          </label>
          <button disabled={busy}>Verify</button>
        </form>
        <Notice>{message}</Notice>
      </>
    );
  }

  return (
    <>
      <h1>Create an account</h1>
      <form onSubmit={signUp}>
        <label>
          Display name
          <input
            autoComplete="name"
            required
            maxLength={80}
            value={displayName}
            onChange={(event) => setDisplayName(event.target.value)}
          />
        </label>
        <label>
          Email
          <input
            type="email"
            autoComplete="username"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
        </label>
        <label>
          Password
          <input
            type="password"
            autoComplete="new-password"
            required
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
        </label>
        <button disabled={busy}>Create account</button>
      </form>
      <Notice>{message}</Notice>
      <p>
        <a href={withQuery('/login')}>Back to sign in</a>
      </p>
    </>
  );
}

// Gate G9 only: shows what requesting a reset reveals. Finishing a reset is 5C.
function ResetPage() {
  const [email, setEmail] = useState('');
  const { busy, message, run } = useAsyncAction();

  const submit = (event) => {
    event.preventDefault();
    run(async (show) => {
      const { error } = await authClient.forgetPassword.emailOtp({ email });
      if (error) throw error;
      show('Request accepted.');
    });
  };

  return (
    <>
      <h1>Forgot password</h1>
      <form onSubmit={submit}>
        <label>
          Email
          <input
            type="email"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
        </label>
        <button disabled={busy}>Send reset code</button>
      </form>
      <Notice>{message}</Notice>
      <p>
        <a href={withQuery('/login')}>Back to sign in</a>
      </p>
    </>
  );
}

function ConsentPage() {
  const params = useMemo(() => new URLSearchParams(window.location.search), []);
  const [clientName, setClientName] = useState(null);
  const { busy, message, run } = useAsyncAction();
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

  return (
    <>
      <h1>Allow access?</h1>
      <dl>
        <dt>App</dt>
        <dd>{clientName ?? clientId ?? 'Unknown'}</dd>
        <dt>Returns to</dt>
        <dd>{callbackHost}</dd>
        <dt>Permissions</dt>
        <dd>{params.get('scope') ?? 'Unknown'}</dd>
        <dt>For</dt>
        <dd>{params.get('resource') ?? 'Unknown'}</dd>
      </dl>
      <div className="actions">
        <button disabled={busy} onClick={() => respond(true)}>
          Allow
        </button>
        <button disabled={busy} onClick={() => respond(false)}>
          Deny
        </button>
      </div>
      <Notice>{message}</Notice>
    </>
  );
}

function SignOutPage() {
  const { busy, message, run } = useAsyncAction();
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
      <button disabled={busy} onClick={signOut}>
        Sign out of VeloraUG sign-in
      </button>
      <Notice>{message}</Notice>
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

const pages = {
  '/login': LoginPage,
  '/sign-up': SignUpPage,
  '/reset': ResetPage,
  '/consent': ConsentPage,
  '/sign-out': SignOutPage,
  '/auth/callback/android': AndroidCallbackPage,
};

export function App() {
  const Page = pages[window.location.pathname];
  return (
    <main>
      {Page ? <Page /> : <p>Open this site from the VeloraUG app.</p>}
    </main>
  );
}
