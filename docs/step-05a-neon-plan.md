# Step 5A plan: Neon database and accounts

Date: 3 November 2026. This plans Milestone 5 in the [roadmap](roadmap.md) and replaces the [Supabase plan](step-05a-plan.md), which is kept as history. **Milestone 5 is not complete, and nothing here is implemented.** No Neon or Cloudflare resource was created or changed, no migration was run, nothing was deployed and no dependency was added. All SQL and code below are drafts that have never run.

Neon behaviour comes from the [official pages listed at the end](#sources) and the published `@neon/auth` 0.8.2 package, as read on this date. Nothing was tested against a real Neon project, so anything that needs one is listed under [gates](#step-5b-gates) or [still unconfirmed](#still-unconfirmed).

## Summary

- **Neon has no Flutter or Dart SDK, and its roadmap does not list one.** Its SDK is TypeScript.
- **Neon's roadmap says separate frontend and backend deployments are "not yet supported"** when they rely on its session cookies. VeloraUG is that kind of architecture.
- **The documented route that fits is Neon's OAuth Provider.** Its guide lists `public` clients with PKCE for "single-page, mobile, desktop, and CLI apps", and has your API verify the resulting JWT. Flutter and FastAPI then never touch Neon's session cookie.
- **That route has three costs:**
  1. We must host a small login and consent website, using `@neon/auth`.
  2. `veloraug://` callbacks are refused, so Android needs an HTTPS callback and a verified web host.
  3. The feature is documented for this use, but nothing here has run against a real project, so [Step 5B](#step-5b-gates) proves it before other work starts.
- **Flutter never reaches the database.** It talks to FastAPI, and FastAPI talks to Neon Postgres with a restricted role. The Data API stays off.
- **Cloudflare R2 stays** as movie storage. Neon Object Storage is not used.

## Implementation sequence

Each step needs the one before it, except that 5E and 5F can swap.

| Step | Scope | Finished when |
| --- | --- | --- |
| **5A**, this step | This plan and the example configuration | Committed locally |
| **5B** | Neon development branch, minimal auth pages on Cloudflare Pages, and a throwaway sign-in on web and one phone | Every [gate](#step-5b-gates) has a recorded result. **Failure on G3 to G6 stops the milestone until the owner decides** |
| **5C** | Finished auth pages: sign-up, email code, sign-in, reset, consent, sign-out | [5C criteria](#5c-auth-pages) pass |
| **5D** | Flutter sign-in, session storage, refresh and sign-out on web and Android | [5D criteria](#5d-flutter) pass |
| **5E** | FastAPI token verification, `GET /api/v1/me` returning the verified ID, CORS | [5E criteria](#5e-token-verification) pass |
| **5F** | Alembic, the app database role, `profiles`, row-level security, and profile reads and updates | [5F criteria](#5f-database-and-isolation) pass |
| **5G** | End-to-end checks on web and Android, the report, and closing the milestone | [5G criteria](#5g-end-to-end) pass |

Not in Milestone 5: subscriptions, payment tables, admin roles, social sign-in, magic links, passwordless sign-in, account deletion, production resources.

## Decisions

| # | Decision | Why |
| --- | --- | --- |
| 1 | One Neon project. A `development` child branch is used now, and the default branch stays empty until the pilot | Each branch has its own Auth URL, users and settings. Branching later from production would copy real users into the copy, so `development` is created while the parent is empty |
| 2 | Flutter signs in through OAuth 2.1 authorization code with PKCE, as a `public` client | The documented route for single-page and mobile apps. No secret ships in the app |
| 3 | Flutter never sees a password. Passwords are typed only on our hosted auth pages | The pages use the supported SDK, and FastAPI never handles passwords either |
| 4 | Email verification and reset use **codes, not links** | Codes work on Neon's shared email service, and links do not. Codes need no deep link back to the app |
| 5 | Android callback is an HTTPS address, verified with Digital Asset Links | Managed clients refuse custom schemes, and Android Auth Tab refuses `http` |
| 6 | Consent stays on | Neon says not to skip it for public clients. Users approve once, and later sign-ins reuse the stored consent |
| 7 | FastAPI verifies JWTs locally with PyJWT and JWKS | Neon's own Python sample uses PyJWT with EdDSA. No secret is needed to verify |
| 8 | FastAPI connects with a SQL-created role that has no `BYPASSRLS` | Roles created in the Neon Console, CLI or API inherit `neon_superuser`, which bypasses row-level security |
| 9 | Migrations use Alembic with hand-written SQL, over a direct connection | Neon's Python migration guide uses Alembic, and says migrations need a direct connection |
| 10 | The Data API stays off | Everything goes through FastAPI, so there is no second path into the data to secure |
| 11 | `profiles` has **no foreign key** into `neon_auth`, and no trigger on it | Neon's docs don't describe either, and that schema is Neon's to manage. See [profile creation](#profile-rows) |
| 12 | The Python app still doesn't load `.env` itself. Docker Compose passes settings | Keeps the existing test and setup valid |

### Routes ruled out

These are routes within Neon, not other providers. They are recorded so nobody rediscovers them as shortcuts.

| Route | Why not |
| --- | --- |
| `@neon/auth` inside Flutter | TypeScript only |
| Dart calling the Better Auth endpoints directly, with cookies | The session cookie is HTTP-only, so Flutter web can't read it. No Neon page documents a native-app session contract, and Neon says its wrapper is not interchangeable with a bare Better Auth client |
| Community Dart Better Auth packages | Not from Neon. They assume a Better Auth server you run yourself |
| FastAPI proxying sign-in | Puts passwords through the API. Neon's server toolkit is JavaScript only, and beta |
| The JWT plugin from Flutter | Getting that token needs the session cookie first. It also has no `resource` audience |
| `veloraug://auth-callback` | "Any other URI, including custom schemes such as `myapp://`, makes the request fail" for managed clients |
| Loopback callback on Android | Allowed by Neon, but Auth Tab refuses `http`, and it depends on localhost access, which goes off in production |

## 1. Architecture of sign-in

```text
Flutter app            Auth pages              Neon Auth              FastAPI        Neon Postgres
(web, Android)         (Cloudflare Pages)      (development branch)

1. opens /oauth2/authorize with PKCE and resource ------>
                       <--- 2. no session: redirect with signed query
                       3. user signs in with @neon/auth, session cookie set -->
                       4. oauth2.continue, then consent page, oauth2.consent ->
<---- 5. redirect to the callback with code and state ---
6. POST /oauth2/token with code and verifier ----------->
<---- 7. access token (1 hour) and refresh token (30 days) ---
8. API call with Authorization: Bearer <token> ----------------------->
                                                       9. verify with cached JWKS
                                                       10. set app.user_id ------> RLS applies
```

The session cookie stays between the auth pages and Neon. **Flutter and FastAPI only ever see OAuth tokens,** which is why the roadmap's cookie limit doesn't block this design. It still affects the auth pages themselves: see [G4](#step-5b-gates).

## 2. Auth pages

**New folder `apps/auth_pages/`, created in 5B.** It is a Vite and React site, because that is what Neon supports, with exactly pinned `@neon/auth` 0.8.2 (0.8.0 or later handles `oauth_query` for you). This adds a `package.json` to the repository. Neon hosts the auth server, so the site never calls `betterAuth()` and has no database access.

```ts
import { createAuthClient } from '@neon/auth';
import { BetterAuthReactAdapter } from '@neon/auth/react/adapters';

export const authClient = createAuthClient(import.meta.env.VITE_NEON_AUTH_URL, {
  adapter: BetterAuthReactAdapter({ fetchOptions: { credentials: 'include' } }),
});
```

Pass `credentials` through the adapter, as above. Neon's JWT page puts `fetchOptions` directly on `createAuthClient`, but in the 0.8.2 source that path forwards only `headers`, so `credentials` would be dropped. Only reading the source supports this, so 5B confirms that the cookie is actually sent.

| Page | Calls | Notes |
| --- | --- | --- |
| `/login` | `signIn.email`. On load with a session: `oauth2.continue({ selected: true })` | One generic failure message |
| `/sign-up` | `signUp.email`, then `emailOtp.verifyEmail` | Auto sign-in after verification, then `oauth2.continue`. Keep the signed query in the address |
| `/reset` | `forgetPassword.emailOtp`, `emailOtp.checkVerificationOtp` with `forget-password`, `emailOtp.resetPassword` | Neon says `resetPasswordForEmail` is not fully supported, so it is not used |
| `/consent` | `oauth2.consent({ accept })`, with client name from `oauth2.publicClient` | Show the client name, callback host, scopes and resource, as Neon's guide requires |
| `/sign-out` | `signOut`, then return to the app | See [sign-out](#sign-out) |
| `/auth/callback/android` | No sign-in logic | App Link target. If Android doesn't open the app, this page explains what to do |

Rules:

- **Pass the signed query back unchanged,** and never build consent addresses by hand. The SDK does both.
- **Never use `prompt=login` or `max_age=0`.** Neon documents that they loop back to the login page.
- **Send `Content-Security-Policy: frame-ancestors 'none'` as a real response header,** using a Cloudflare Pages `_headers` file. Neon's guidance is that a `<meta>` tag is ignored.
- Serve `public/.well-known/assetlinks.json` for Android. It holds only the app ID and certificate fingerprint, which are public.

**Hosting.** Cloudflare Pages is already in the architecture. This moves one small site forward from Milestone 10, on a free `*.pages.dev` address, so no domain is needed yet. Direct upload with `npx wrangler pages deploy`, run by the owner. The Flutter web build still waits for Milestone 10.

## 3. Flutter on web and Android

**Packages, pinned in 5D after the gates:** `flutter_web_auth_2` (5.1.0 when checked) for the browser step, the existing `http` for token calls, `crypto` for the PKCE hash, and `flutter_secure_storage` (11.2.0 when checked) on Android. None comes from Neon. `flutter_appauth` has no web support, and `oauth2` can't send the `resource` parameter, which Neon requires.

| Request | Values |
| --- | --- |
| Authorize | `response_type=code`, `client_id`, `redirect_uri`, `scope=openid email offline_access`, `state`, `code_challenge`, `code_challenge_method=S256`, `resource` |
| Exchange | `grant_type=authorization_code`, `code`, `code_verifier`, `redirect_uri`, `client_id`, `resource`, form-encoded, with no client secret |
| Refresh | `grant_type=refresh_token`, `refresh_token`, `client_id` |

Endpoints come from `<issuer>/.well-known/oauth-authorization-server`, and the app checks that `issuer` equals its setting. **Without `resource`, Neon issues an opaque token that FastAPI cannot verify.**

Neon's sample for this exchange is a confidential client, so the exact public-client request is [gate G5](#step-5b-gates).

| | Web | Android |
| --- | --- | --- |
| Browser step | Popup. The package requires a page at `apps/client/web/auth.html` that posts the result back to the same origin | Chrome Auth Tab, Chrome 137 or later |
| Callback | `http://localhost:8765/auth.html`, later the production web address | `https://<pages host>/auth/callback/android` |
| Token storage | Memory and `sessionStorage`, which survive a reload but not a closed tab | `flutter_secure_storage` |
| New launch | A new sign-in round. No form appears if the Neon session is still valid | Refresh token |

**Refresh tokens rotate, and reuse is punished.** Each refresh returns a new token, and Neon's guide warns that presenting an already-rotated token revokes that user's refresh tokens for the client. So:

- Only one refresh may run at a time on a device. Others wait for its result.
- Keeping tokens per tab on the web is deliberate: each tab has its own, so tabs can't collide.
- Don't set `mcp.resource` to get the 30-second reuse window. There is no MCP server here.
- A failed refresh means sign-in again, not a retry loop.

**Web storage is readable by scripts on the page.** A cross-site scripting bug could steal these tokens, and encrypting them in the browser wouldn't change that. Mitigations are the per-tab scope, no third-party scripts, and a content security policy when the web app is hosted in Milestone 10.

**Android.** Add to the main manifest in 5D:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

```xml
<activity android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
          android:exported="true" android:taskAffinity="">
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW"/>
        <category android:name="android.intent.category.DEFAULT"/>
        <category android:name="android.intent.category.BROWSABLE"/>
        <data android:scheme="https" android:host="YOUR-PAGES-PROJECT.pages.dev"
              android:path="/auth/callback/android"/>
    </intent-filter>
</activity>
```

- Set `android:allowBackup="false"`. `networkSecurityConfig` stays in `src/debug/` only, and `usesCleartextTraffic` is never added.
- The development app keeps `com.example.veloraug`. Its debug certificate fingerprint goes in the development `assetlinks.json`. The production ID and signing certificate are added before release, on a production host.
- Below Chrome 137, or with another default browser, Auth Tab falls back to a Custom Tab, and support varies. That behaviour is recorded in G6, on one phone only.

**Other client rules:**

- Validate `NEON_AUTH_URL` and `AUTH_PAGES_URL` as `parseApiBaseUrl` does, but HTTPS only.
- With missing settings, show "Sign-in is not configured" rather than crashing, so `flutter test` works without a project.
- Never log a token.
- Change the test `account offers no sign-in or payment controls`. The checks for payment wording stay.

### Sign-out

Three things are separate, and all three must happen:

1. **Revoke the refresh token** at `<issuer>/oauth2/revoke`. Confirmed in G8.
2. **Clear the device.** This always happens, even with no network.
3. **End the Neon browser session** by opening `/sign-out` on the auth pages. Otherwise the next sign-in skips the form and returns the same user, which is wrong on a shared device. `prompt=login` can't replace this, as noted above.

## 4. Token verification in FastAPI

**Use these rules, not Neon's JWT plugin sample.** That sample checks `iss` and `aud` against the origin of the Auth URL, because plugin tokens are built that way. OAuth tokens use the full issuer URL and the resource as audience. The sample also fetches keys on every call, which Neon says isn't production-ready.

| Check | Rule |
| --- | --- |
| Algorithm | Fixed list `["EdDSA"]` in the code. Never from the token or from settings |
| Signature | A key from `<issuer>/.well-known/jwks.json` only. Key addresses inside a token are never followed |
| Issuer | **Exact match** with `VELORAUG_NEON_AUTH_URL`. All branches of a project share signing keys, so this is what separates them |
| Audience | Must contain `VELORAUG_API_RESOURCE`. `aud` can be an array, so `strict_aud` must stay off |
| Expiry | Required. Also require `iat`, `iss`, `aud` and `sub`, because PyJWT only checks some claims if present. Confirm `iat` in G7 |
| Client | `client_id` must be in `VELORAUG_NEON_AUTH_CLIENT_IDS` |
| User | `sub` must parse as a UUID, subject to G7. Nothing else in the token decides access |

Illustrative only:

```python
ALGORITHMS = ["EdDSA"]

signing_key = jwks_client.get_signing_key_from_jwt(token).key
claims = jwt.decode(
    token,
    signing_key,
    algorithms=ALGORITHMS,
    issuer=settings.neon_auth_url,
    audience=settings.api_resource,
    options={"require": ["exp", "iat", "iss", "aud", "sub"]},
)
if claims.get("client_id") not in settings.neon_auth_client_ids:
    raise InvalidToken
user_id = UUID(claims["sub"])
```

- Never use `verify_signature: False`, and never treat decoding as verification.
- Use a plain `def` dependency, like the existing routes. `PyJWKClient` and `psycopg` both block, so FastAPI's thread pool is the right place.
- `PyJWKClient`: `timeout=5` and cached keys. An unknown `kid` refetches once, as Neon advises, with a limit so invented `kid` values can't force constant fetching. Confirm how in the pinned version.
- Pin `PyJWT[crypto]`, because EdDSA needs `cryptography`. Latest when checked: PyJWT 2.15.1 and cryptography 50.0.2. Check ARM64 in Milestone 10.

| Situation | Response |
| --- | --- |
| No header, wrong scheme, or any invalid token | `401` with `WWW-Authenticate: Bearer`. The body doesn't say which check failed |
| Keys can't be fetched, or the database is unavailable | `503`, and access is refused |
| Production without the auth or database settings | The API refuses to start |

`/health` and `/api/v1` stay public, and `/health` doesn't touch the database. CORS adds `allow_methods=["GET", "PATCH"]` and `allow_headers=["Authorization", "Content-Type"]`. Credentials stay off, because the API uses no cookies.

### Revocation limits

- **An access token stays valid until `exp`, up to one hour,** and lifetimes aren't configurable. Local verification can't see a sign-out or a ban.
- Disabling or deleting an OAuth client doesn't revoke tokens already issued.
- This is acceptable for reading a profile. Milestones 8 and 9 must decide what sensitive actions need, such as a live database check. Neon has no custom claims, and the `introspect` endpoint is aimed at clients with credentials, so neither is assumed here.

## 5. Authorization and user data isolation

**Authentication** says who the user is, using the verified `sub`. **Authorization** is decided by FastAPI from VeloraUG's own tables, never by the token or the app.

| Layer | Rule |
| --- | --- |
| No direct access | Flutter has no database address. The Data API is off. `veloraug_app` has no rights on `neon_auth` |
| Identity source | The user ID comes only from the verified token, never from a path, query or body |
| Queries | Every user-owned query filters on that ID |
| Row-level security | The database refuses other users' rows even if a query forgets the filter |
| Column rights | The app role can change only the agreed columns |

Later milestones extend this and don't weaken it. Roles and paid access go in VeloraUG tables, because Neon doesn't support custom claims. Pesapal callbacks and the media worker have no user token, so they get their own narrow role when they are designed, not `veloraug_app` with RLS switched off.

**Passing the user to Postgres.** Neon's pooler uses transaction mode, so session settings can't be trusted across requests. Each request therefore runs in one transaction, and the setting ends with it:

```python
with pool.connection() as conn, conn.transaction():
    conn.execute("select set_config('app.user_id', %s, true)", (str(user_id),))
    # the request's queries run here
```

`auth.user_id()` is not used, because it comes from the Data API, which is off.

### Database roles

| Role | Connection | Used by | Rights |
| --- | --- | --- | --- |
| `neondb_owner`, Neon's default | **Direct** | Migrations only, from the owner's machine | Owner, inherits `BYPASSRLS` |
| `veloraug_app`, created with SQL | **Pooled** (`-pooler`) | The API | Only what migrations grant. No `BYPASSRLS` |

Each branch gets its own `veloraug_app` password. Child branches copy roles and passwords from the parent, so the password must be changed on any branch that later holds real data. Neon Auth can't run with IP Allow, so the database address is reachable from the internet. That makes long generated passwords and TLS essential: keep `sslmode=require&channel_binding=require` from the Console's connection string.

### First migration

**Draft only, never run.** 5F must test it.

```sql
create function public.current_app_user_id()
returns uuid language sql stable set search_path = '' as $$
  select nullif(current_setting('app.user_id', true), '')::uuid
$$;

create table public.profiles (
  user_id uuid primary key,
  display_name text check (
    display_name is null or char_length(display_name) between 1 and 80
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.profiles force row level security;

revoke all on table public.profiles from public;
grant select on table public.profiles to veloraug_app;
grant insert (user_id) on table public.profiles to veloraug_app;
grant update (display_name) on table public.profiles to veloraug_app;

create policy profiles_select_own on public.profiles
  for select to veloraug_app
  using (user_id = public.current_app_user_id());

create policy profiles_insert_own on public.profiles
  for insert to veloraug_app
  with check (user_id = public.current_app_user_id());

create policy profiles_update_own on public.profiles
  for update to veloraug_app
  using (user_id = public.current_app_user_id())
  with check (user_id = public.current_app_user_id());

create function public.set_profile_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_profile_updated_at();

revoke all on function public.set_profile_updated_at() from public;
```

With no `app.user_id` set, the function returns null, nothing matches, and no rows are visible. `neondb_owner` still bypasses these policies, so only the migration connection may use it.

### Profile rows

- `GET /api/v1/me` runs `insert into public.profiles (user_id) values (...) on conflict do nothing`, then reads the row. This replaces the Supabase trigger: Neon documents no triggers on `neon_auth`, and a `user.created` webhook would need a public endpoint and can fail silently.
- `PATCH /api/v1/me` changes `display_name` only.
- **Deleting a Neon Auth user does not remove their profile.** There is no foreign key, and Neon's webhook list has no user-deleted event. Account deletion is out of scope here. When it is built, it must remove VeloraUG's rows too.

## 6. Migrations

**Location:** `services/api/migrations/`, created in 5F, tracked in Git. Alembic, SQLAlchemy and the driver go in a new `requirements-migrate.txt`, so the API image doesn't carry migration tools. Latest when checked: Alembic 1.20.1, SQLAlchemy 2.1.6, psycopg 3.3.7. Migrations are hand-written `op.execute` SQL, with no autogenerate, because the API has no ORM models.

```powershell
cd C:\Users\Wilsoft\veloraug\services\api
$env:VELORAUG_MIGRATION_DATABASE_URL = Read-Host "Direct owner URL" # the owner pastes it
.\.venv\Scripts\python.exe -m alembic current
.\.venv\Scripts\python.exe -m alembic upgrade head --sql  # read the SQL
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m alembic current
Remove-Item Env:VELORAUG_MIGRATION_DATABASE_URL
```

Rules:

- **The owner runs migrations,** so the owner's database password stays out of tool sessions.
- **`env.py` prints the host and refuses a `-pooler` host.** Check the host before every run. Never point this at a Neon project used by `C:\Users\Wilsoft\velora`, or any other unrelated one.
- **Test on a throwaway branch first:** `neon branches create --name migration-test --parent development`, run the migration and tests there, then delete it.
- **Don't change the schema in the Console.** It bypasses migration history.
- **Don't edit an applied migration,** and don't run `downgrade` on a hosted branch. Fix mistakes with a new one.
- **Never touch `neon_auth`.** It belongs to Neon.
- **Don't use `neon env pull` for the API settings.** It writes owner credentials into a `.env` file, and the API must use `veloraug_app`.
- `veloraug_app` gets no rights on `alembic_version`.

The CLI runs through a pinned `npx` as before, for example `npx --yes neon@8.17.1 <command>` (latest when checked). `neon link` writes a `.neon` file, which is now ignored by Git.

## 7. Email

| | Neon shared service | Custom SMTP |
| --- | --- | --- |
| Verification codes | Works | Works |
| Verification links | **Doesn't work** | Works |
| Password reset | Works | Works |
| Suitable for | Development and testing only. Rate-limited, and the limit isn't published | Real users |

**5B to 5G use the shared service.** Pace the tests, because a missing email doesn't prove the code is wrong. **Before real users,** custom SMTP is required, which in practice means a sender domain. No domain is recorded for this project. SMTP credentials go in the Neon Console only. A custom provider still uses Neon's default templates. Full control needs the `send.otp` webhook, which is not planned.

## 8. Movie storage: unchanged

Cloudflare R2 remains private, and viewers only reach video through the Worker. Neon replaces only the sign-in check and the database behind FastAPI.

- FastAPI verifies the Neon token and checks access in Postgres, then grants playback. That design is still due before Milestone 8.
- The Worker doesn't need Neon credentials or the Neon token unless the Milestone 8 design says so.
- Postgres stores R2 object keys, not video. R2 keys stay with the services that use them, and never reach Flutter.

## 9. Cost

From Neon's plans page, not measured. Free: 100 CU-hours and 1 GB per project, 5 GB of network transfer per project, scale to zero after 5 minutes, and up to 60,000 monthly active auth users. Launch has no minimum fee, and charges $0.106 per CU-hour and $0.35 per GB-month. An SMTP provider and a domain would add cost. Milestone 10 still measures this against the $20 target.

A database that has scaled to zero takes a moment to wake, so the API needs a `connect_timeout` and must return `503` rather than hang.

## Configuration

**Nothing reads these settings yet.** Public values are safe to expose, because anyone can extract them from a built app. **Flutter and the auth pages may hold public values only.**

### Public

| Variable | Used by | Purpose | Source | Goes in |
| --- | --- | --- | --- | --- |
| `API_BASE_URL` | Flutter | FastAPI address | Local address, later HTTPS | `apps/client/dart_defines.local.json` |
| `NEON_AUTH_URL` | Flutter | OAuth issuer | Neon Console: branch, Auth, Configuration | Same |
| `NEON_AUTH_WEB_CLIENT_ID` | Flutter | Web client ID | [Setup step 7](#3-in-neon-after-the-pages-exist) | Same |
| `NEON_AUTH_ANDROID_CLIENT_ID` | Flutter | Android client ID | Setup step 7 | Same |
| `API_RESOURCE` | Flutter | Token audience | [Setup step 6](#3-in-neon-after-the-pages-exist) | Same |
| `AUTH_PAGES_URL` | Flutter | Callback and sign-out host | Cloudflare Pages | Same |
| `VITE_NEON_AUTH_URL` | Auth pages | Same issuer | Neon Console | `apps/auth_pages/.env.local` |
| `VELORAUG_NEON_AUTH_URL` | API | Expected issuer, and JWKS address | Neon Console | `services/api/.env` |
| `VELORAUG_API_RESOURCE` | API | Expected audience | Setup step 6 | Same |
| `VELORAUG_NEON_AUTH_CLIENT_IDS` | API | Allowed clients, as a JSON list | Setup step 7 | Same |

OAuth client IDs of `public` clients are not secrets. They have no client secret at all.

### Secrets

Never in Flutter, the auth pages, Git or a chat.

| Variable | Used by | Purpose | Source | Goes in |
| --- | --- | --- | --- | --- |
| `VELORAUG_DATABASE_URL` | API | Pooled connection as `veloraug_app` | Console **Connect**, pooled, with that role | `services/api/.env`, later the Oracle `.env` |
| `VELORAUG_MIGRATION_DATABASE_URL` | Alembic only | Direct connection as `neondb_owner` | Console **Connect**, direct | The owner's terminal, for that run only. **Never in the API's environment** |
| `veloraug_app` password | Owner | Set per branch | The owner's password manager | Inside the URL above |
| SMTP credentials, later | Neon | Sends auth email | Email provider | Neon Console only |
| Neon API key, if ever used | Owner | CLI in scripts | Neon Console | Not planned. `neon` signs in through the browser |

**Not needed at all:** `NEON_AUTH_COOKIE_SECRET`, which is for Next.js apps, and OAuth client secrets, which public clients don't have. R2, Pesapal, TMDB and Telegram secrets are unchanged and stay as in the [architecture](architecture.md#where-configuration-and-secrets-will-live).

`python-dotenv` remains unused by the app. Under Docker Compose, the 5E change adds `env_file: [{path: ../services/api/.env, required: false}]` to `infra/compose.local.yaml`. The `.dockerignore` allowlist already keeps `.env` out of the image. Run directly with Python, the settings are set in that terminal.

## Owner setup

Nothing here is done. These steps come before 5B, except where noted. **Don't paste any password or connection string into a chat.** The Auth URL, client IDs, region and fingerprint are public and can be shared.

### 1. Decide

| Question | Default | Why it matters |
| --- | --- | --- |
| Neon region | `aws-eu-central-1` (Frankfurt), **if the Oracle server is in or near Europe** | It can't be changed after creation. Managed Auth runs in the same region. Tell me the Oracle region if it's elsewhere. The default is my judgement for users in Uganda, not a measurement |
| Cloudflare Pages name | `veloraug-auth-dev` | Becomes the public address. It goes into Neon settings, the manifest and `assetlinks.json` |
| Two test mailboxes | Yours to choose | One you can open on the computer and the phone, and a second for the second user |
| Is display name the right first profile field? | Yes | The table adds only what is agreed |

### 2. In Neon

1. Sign up or sign in at [console.neon.tech](https://console.neon.tech). The Free plan is enough for now.
2. **Create a project** named `veloraug`, in the chosen AWS region. Leave IP Allow and Private Networking off, because Auth doesn't work with them. **Don't enable the Data API.** Don't reuse an existing project.
3. **Create a child branch** named `development` while the default branch is empty.
4. **On `development` only, enable Auth.** Copy the Auth URL: this is `NEON_AUTH_URL`. Don't build it by hand.
5. **Under Settings, Better Auth,** on `development`: turn on **Sign-up with Email** and **Verify at Sign-up**, and choose **Verification code**. Keep auto sign-in after verification on. Set the application name to `VeloraUG Dev`. Keep **Allow Localhost** on. Add no social providers.

### 3. In Neon, after the pages exist

I build the pages in 5B, you deploy them and then run these. Each command needs your Neon sign-in. Confirm the flags with `--help` on the pinned version. The Console has the same settings.

6. Add the trusted domain and protected resource. `api-dev.veloraug.invalid` is an identifier only, and Neon's docs say a resource doesn't need to resolve. The `.invalid` ending is reserved, so it can never belong to anyone. G2 confirms Neon accepts it.

   ```powershell
   npx --yes neon@8.17.1 neon-auth domain add https://veloraug-auth-dev.pages.dev --branch development
   npx --yes neon@8.17.1 neon-auth config oauth-server resource add https://api-dev.veloraug.invalid --branch development
   npx --yes neon@8.17.1 neon-auth config oauth-server update --enabled --login-page https://veloraug-auth-dev.pages.dev/login --consent-page https://veloraug-auth-dev.pages.dev/consent --branch development
   ```

7. Create two public clients, and copy each client ID. **Don't use `--skip-consent`.**

   ```powershell
   npx --yes neon@8.17.1 neon-auth oauth-client create --name "VeloraUG Web Dev" --type public --redirect-uris http://localhost:8765/auth.html --resources https://api-dev.veloraug.invalid --branch development
   npx --yes neon@8.17.1 neon-auth oauth-client create --name "VeloraUG Android Dev" --type public --redirect-uris https://veloraug-auth-dev.pages.dev/auth/callback/android --resources https://api-dev.veloraug.invalid --branch development
   ```

### 4. In Cloudflare

8. Sign in with `npx wrangler login` when 5B asks, and deploy with the command 5B provides. Your account's other projects aren't touched.

### 5. On this computer

9. **Get the debug certificate fingerprint,** and tell me the `SHA-256` line of the `debug` variant. It isn't secret.

   ```powershell
   cd C:\Users\Wilsoft\veloraug\apps\client\android
   .\gradlew.bat signingReport
   ```

10. **Copy the example files** and fill them in: `apps/client/dart_defines.example.json` to `apps/client/dart_defines.local.json`, and `services/api/.env.example` to `services/api/.env`. Leave the database lines until step 11. `git check-ignore` confirms both copies are ignored.

### 6. At 5F

11. **Create `veloraug_app`** on `development`. 5F provides a small local script that prompts for the password, so it stays out of the Neon SQL Editor's history. Save the password in a password manager, then put the pooled connection string in `services/api/.env`.
12. **Run the migration yourself,** using [the commands above](#6-migrations).

### Needed before real users, not now

A production web address, the production Android ID and signing certificate, a sender domain and SMTP provider, Auth and OAuth clients on the default branch with its own Pages host, and **Allow Localhost turned off there**.

## Step 5B gates

These settle what Neon's docs leave open. They are checked against the `development` branch, and each result is recorded in the 5B report.

| # | Question | Pass | If it fails |
| --- | --- | --- | --- |
| G1 | Does issuer metadata match the Auth URL, and does JWKS list an Ed25519 key? | Both yes | Stop and report |
| G2 | Does Neon accept the `.invalid` resource, and issue a JWT rather than an opaque token? | Yes | Use another address on a domain the owner controls |
| G3 | Do sign-up, email code and sign-in on the pages resume the signed query through consent? How long does that query last? | Reaches the callback | **Stop.** Owner decides |
| G4 | Does the session survive between the pages and `/oauth2/authorize`, given the cross-site cookie? Test Chrome and Edge on the computer, and Chrome on the phone. Also Firefox, and Safari if one is available | Required browsers pass. Others recorded | **Stop** if Chrome fails. Neon points to reverse-proxy or shared-domain workarounds, and those need a new plan. Other browsers: owner decides whether that's acceptable |
| G5 | Can a public client exchange and refresh from `http://localhost:8765`, including browser CORS? | Web and Android both work | **Stop.** Don't route tokens through FastAPI without a new decision |
| G6 | Does Auth Tab return the HTTPS callback to the app after Digital Asset Links verification, on one phone? Is a return button needed on the callback page? | Code reaches the app | **Stop.** Record the Chrome version and default browser |
| G7 | What does a real token contain: `sub` format, `iat`, `aud` shape, `client_id`? | Recorded, with secret values excluded | Adjust the checks and the `user_id` type before 5E and 5F |
| G8 | Do revoke and `/sign-out` work for a public client, and does the next sign-in show the form? | Yes | Try `end-session`, and record the limit |
| G9 | What do sign-up and reset reveal about whether an address has an account? | Recorded | The pages use neutral wording where the server allows it. Report any leak the pages can't hide |

**Stop rule.** The fallback for a failed gate is a decision, not a workaround. Don't reimplement Better Auth in Dart, handle Neon's cookies in Flutter, skip consent, or add a proxy without a revised plan.

## Acceptance criteria

Manual results must be labelled as user-reported, as in earlier reports. **Web** means `flutter run -d web-server --web-hostname localhost --web-port 8765 "--dart-define-from-file=dart_defines.local.json"`, opened in a normal Chrome profile. `flutter run -d chrome` uses a temporary profile, so it can't test session restore. **Android** means a real phone.

### 5C auth pages

- [ ] Sign-up sends a code, and no session exists until the code is entered
- [ ] A wrong or expired code shows an error, with an offer to send a new one
- [ ] A wrong password and an unknown address show the same message
- [ ] Reset by code changes the password: the old one fails, and the new one works
- [ ] The consent page shows client, callback host, scopes and resource, and denying returns an error to the app
- [ ] The second sign-in doesn't ask for consent again
- [ ] An expired signed query gives a clear message and a way back to the app
- [ ] `frame-ancestors 'none'` is present as a response header
- [ ] `assetlinks.json` is served with the right content
- [ ] A search of the built site finds no secret, and it has no database address

### 5D Flutter

- [ ] Sign-in works on web and Android, and the app verifies `state`
- [ ] A changed `state`, a cancelled browser and a denied consent each leave the user signed out, with a message
- [ ] The session survives a reload on web, and a full close and reopen on Android
- [ ] Web closed and reopened either restores silently or shows sign-in, and the result is recorded
- [ ] Two simultaneous calls near expiry cause one refresh only (automated)
- [ ] A refused refresh signs the user out instead of looping (automated)
- [ ] Sign-out meets [all three parts](#sign-out), and sign-out with no network still clears the device
- [ ] No token appears in logs
- [ ] The merged release manifest has `INTERNET`, no `networkSecurityConfig` and no `usesCleartextTraffic`
- [ ] The debug manifest keeps its loopback rule, and the Step 4C phone check still passes
- [ ] `allowBackup` is `false`
- [ ] Format, analyze, tests and web and APK builds pass
- [ ] Searching the web build and APK for `postgresql://`, `npg_`, `neondb_owner` and `VELORAUG_` finds nothing

### 5E token verification

Automated tests use a locally generated Ed25519 key and a local JWKS, so they need no network or real project.

**A token must get `401` when it is:**

- [ ] Missing, or sent with a scheme other than `Bearer`
- [ ] Malformed, expired, or tampered with in the payload or signature
- [ ] Signed with `alg: none`, or with HS256 using the public key as the secret
- [ ] Signed with RS256 or ES256, by any key
- [ ] Signed by a different key that claims the right issuer and `kid`
- [ ] Validly signed with another branch's issuer, which is the case Neon warns about
- [ ] Carrying the origin of the Auth URL as issuer, rather than the full URL
- [ ] Carrying the wrong audience, or issued to a client not on the list
- [ ] Missing `exp`, `iat`, `iss`, `aud` or `sub`, or with an invalid `sub`
- [ ] Using an unknown `kid`, without refetching the keys on every attempt

**Other checks:**

- [ ] A valid token returns `200` from `/api/v1/me`, with the `sub` from the token
- [ ] `aud` as a string and as an array containing the resource are both accepted
- [ ] Unreachable keys return `503`, not `200` or `401`
- [ ] `/health` and `/api/v1` stay public, and `/health` makes no database call
- [ ] A preflight from `http://localhost:8765` allows `Authorization` and `PATCH`, and other origins are refused
- [ ] No token or connection string appears in logs or error responses
- [ ] Production refuses to start without the settings
- [ ] `ruff` and `pytest` pass, and the Docker image builds and runs healthy

### 5F database and isolation

**Run on a throwaway branch first, then `development`,** using real connections as `veloraug_app`:

- [ ] `veloraug_app` has `rolbypassrls = false`, isn't a member of `neon_superuser`, and owns nothing
- [ ] It can't read `neon_auth` or change the schema
- [ ] With no `app.user_id`, it reads nothing and writes nothing
- [ ] As user A, it sees A's row, and no row for B, even when asking for B's ID
- [ ] As user A, updating or inserting B's row changes nothing, confirmed as B
- [ ] Changing `user_id`, `created_at` or `updated_at` is refused, and delete is refused
- [ ] `app.user_id` doesn't leak: on the pooled connection, a following transaction sees no user. Repeated with concurrent requests for A and B
- [ ] Prepared statements work through the pooler with the driver's defaults, or the setting is changed and recorded
- [ ] Request-level: A's token can't read or change B's data through any `/me` route, and a user ID in the body is ignored
- [ ] Repeated `GET /me` creates exactly one row, including when two run at once
- [ ] A read-only check of `development` confirms RLS and forced RLS are on, and the grants match
- [ ] `alembic current` matches the repository, and the migration is in Git
- [ ] The `-pooler` refusal in `env.py` works

### 5G end to end

- [ ] Web: sign in, call `/api/v1/me`, update the display name, and see it persist, through real CORS
- [ ] Android: the same, over `adb reverse`
- [ ] Two real users on both platforms see only their own profile
- [ ] Signed out in the app, no token is sent, and `/api/v1/me` returns `401`
- [ ] A real token more than an hour old is refused
- [ ] A real token with one changed character is refused
- [ ] A token captured before sign-out is accepted until `exp`, and this is recorded as [the known limit](#revocation-limits), not a failure
- [ ] A release build signs in on a phone over HTTPS. API calls from a release build wait for an HTTPS API, in Milestone 10
- [ ] No real configuration or credential is tracked, and a search of tracked files finds none

## Still unconfirmed

| Item | Resolved by |
| --- | --- |
| Everything under [gates](#step-5b-gates) | 5B |
| The draft SQL, including `force row level security` with this role setup | 5F |
| That `credentials: 'include'` through the adapter reaches the browser's requests | 5B |
| `flutter_web_auth_2` with verified HTTPS callbacks. Its page requires `httpsHost` and `httpsPath`, but doesn't describe App Link verification | G6 |
| Cloudflare Pages serving `/.well-known/assetlinks.json` as needed | G6 |
| The limit on `PyJWKClient` refetches for unknown `kid` values in the pinned version | 5E |
| psycopg binary wheels for ARM64 | Milestone 10 |
| Exact Console labels | Owner setup |

### Conflicts in Neon's own docs

| Topic | Conflict | This plan |
| --- | --- | --- |
| Separate frontend and backend | The roadmap says not supported. The OAuth Provider guide covers "your own apps and APIs", and the React quick start is a separately hosted app | Treats the cookie limit as real, and uses tokens for Flutter and FastAPI. G4 tests what's left |
| Session cookie | The flow page says `__Secure-neonauth.session_token`, `SameSite=None`. SDK source uses `__Secure-neon-auth`. Troubleshooting says `SameSite=Strict` by default | Never reads or depends on it |
| Token `iss` and `aud` | Plugin tokens use the origin. OAuth tokens use the full issuer and the resource | Uses OAuth tokens and OAuth rules |
| Tokens across branches | The branching page says tokens aren't valid in another branch. The OAuth page says signatures are valid on every branch | Trusts the OAuth page's warning, and always checks `iss` |
| Password reset | The reset page describes links and UI components. The Email OTP page documents codes | Uses the documented code methods |
| Cross-origin client option | The JWT page sets `fetchOptions` on `createAuthClient`. The 0.8.2 source forwards only its `headers` | Passes it through the adapter, and tests it in 5B |

## Sources

Read on 3 November 2026, along with `README.md`, `BUILDING-AN-ADAPTER.md` and the source of the published [`@neon/auth` 0.8.2](https://www.npmjs.com/package/@neon/auth).

**Auth:** [overview](https://neon.com/docs/auth/overview), [about](https://neon.com/docs/auth/about), [roadmap](https://neon.com/docs/auth/roadmap), [authentication flow](https://neon.com/docs/auth/authentication-flow), [OAuth Provider](https://neon.com/docs/auth/guides/plugins/oauth-provider), [JWT](https://neon.com/docs/auth/guides/plugins/jwt), [Email OTP](https://neon.com/docs/auth/guides/plugins/email-otp), [email verification](https://neon.com/docs/auth/guides/email-verification), [password reset](https://neon.com/docs/auth/guides/password-reset), [trusted domains](https://neon.com/docs/auth/guides/configure-domains), [Open API](https://neon.com/docs/auth/guides/plugins/openapi), [webhooks](https://neon.com/docs/auth/guides/webhooks), [branching](https://neon.com/docs/auth/branching-authentication), [production checklist](https://neon.com/docs/auth/production-checklist), [troubleshooting](https://neon.com/docs/auth/troubleshooting), [migrating from Supabase](https://neon.com/docs/auth/migrate/from-supabase), [React quick start](https://neon.com/docs/auth/quick-start/react), [Functions authentication](https://neon.com/docs/compute/functions/authentication).

**Database:** [connection pooling](https://neon.com/docs/connect/connection-pooling), [roles](https://neon.com/docs/manage/roles), [database access](https://neon.com/docs/manage/database-access), [Python](https://neon.com/docs/guides/python), [SQLAlchemy migrations](https://neon.com/docs/guides/sqlalchemy-migrations), [row-level security](https://neon.com/docs/guides/row-level-security), [Data API](https://neon.com/docs/data-api/get-started), [regions](https://neon.com/docs/introduction/regions), [plans](https://neon.com/docs/introduction/plans).

**CLI:** [install](https://neon.com/docs/cli/install), [`neon-auth`](https://neon.com/docs/cli/neon-auth), [`link`](https://neon.com/docs/cli/link).

**Flutter and Android:** [`flutter_web_auth_2`](https://pub.dev/packages/flutter_web_auth_2), [Chrome Auth Tab](https://developer.chrome.com/docs/android/custom-tabs/guide-auth-tab).
