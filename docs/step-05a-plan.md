# Step 5A plan: accounts and database

> **Superseded on 3 November 2026. Do not implement this plan.** The project replaced Supabase with Neon PostgreSQL and Neon Auth before any of this was built. The current plan is the [Neon plan](step-05a-neon-plan.md). This file is kept unchanged below as a record of the earlier plan.

Date: 3 November 2026. This plans Milestone 5 in the [roadmap](roadmap.md). **Milestone 5 is not complete, and nothing in this plan is implemented.** No dependency was installed, no Supabase project was created or changed, and no SQL has been run, including the draft below.

Supabase changes often, so its behaviour here comes from the [official pages listed at the end](#sources), as read on this date. Dashboard labels may differ slightly.

## Work split

| Step | Scope |
| --- | --- |
| **5A**, this step | This plan and the example configuration files |
| **5B** | Project settings, the `profiles` migration, Flutter sign-up, sign-in and recovery on web and Android, and the Android manifest changes |
| **5C** | Bearer-token verification in FastAPI, a protected endpoint, CORS for it, and end-to-end tests |

Not in Milestone 5: subscriptions, payment tables, admin roles, OAuth, magic links, anonymous sign-in and multi-factor sign-in.

## Decisions

| # | Decision | Why |
| --- | --- | --- |
| 1 | Create a new Supabase project for VeloraUG development, and a separate one for production later | Tests and real users stay apart, and no other project is touched |
| 2 | Flutter talks to Supabase Auth directly, using `supabase_flutter` | The API never handles passwords |
| 3 | Use the PKCE flow for email links, and set it explicitly | It is the `supabase_flutter` default, but [one page says implicit](#sources), so the code should not depend on a default |
| 4 | The API verifies tokens locally with public keys (JWKS), **once the project's signing keys are confirmed** | No secret is needed, and no network call per request |
| 5 | The API uses PyJWT, not a Supabase SDK | It only needs to verify tokens |
| 6 | The API does not use a secret or service-role key, or connect to the database, in Milestone 5 | It has no need to, and a key it doesn't hold can't leak from it |
| 7 | The app reads and updates its own profile directly through the Data API | Grants and row-level policies enforce the rules, and both are testable |
| 8 | Android callback: `veloraug://auth-callback` | It doesn't depend on `com.example.veloraug`, which will change. No domain exists yet for an HTTPS link |
| 9 | The `profiles` trigger stores only the user's ID | Sign-up metadata is written by the user, so it is not trusted |
| 10 | No `.env` loading in the Python app. Docker Compose would pass the one setting | See [Configuration](#configuration) |

## 1. Account flows

All calls below come from `supabase_flutter` (latest stable when checked: 2.18.3). 3.0.0 is still a prerelease, so 5B should not use it.

| Flow | Call | What the app does |
| --- | --- | --- |
| Sign up | `signUp(email:, password:, emailRedirectTo: callback)` | Shows "check your email" with neutral wording. It must not reveal whether the address already has an account |
| Confirm email | The user opens the emailed link | Supabase verifies it, then redirects to the callback with `?code=`. The SDK exchanges the code for a session |
| Sign in | `signInWithPassword(email:, password:)` | Shows one generic failure message for a wrong email or password |
| Restore session | Happens during `Supabase.initialize` | Shows signed-in or signed-out from the auth state, and refreshes tokens automatically |
| Sign out | `signOut()`, whose Dart default scope is `local` | Clears this device only. Other devices stay signed in |
| Request a password reset | `resetPasswordForEmail(email, redirectTo: callback)` | Always shows the same message. Supabase doesn't reveal whether the account exists |
| Set a new password | On `AuthChangeEvent.passwordRecovery`, open a new-password screen, then call `updateUser(UserAttributes(password: ...))` | Doesn't continue into the normal app until the password is set or the user signs out |

Keep **Confirm email** on, which is the hosted default. Keep **anonymous sign-ins** off.

### Limits of email links with PKCE

- **Same device and browser.** The secret half of the exchange (the code verifier) is stored where the flow began. A link opened elsewhere fails with `Code verifier could not be found in local storage`.
  - **Confirmation:** the app should say the email may already be confirmed, and offer sign-in.
  - **Recovery:** the app should ask the user to request a new link on this device.
- **Newest link only.** The SDK keeps one verifier at a time, so a new request can replace an earlier one. This is inferred from the SDK source, so 5B should test it.
- **Short exchange window.** The code lasts 5 minutes and works once.
- **Email scanners.** Some mail providers open links automatically, which can use up a one-time link. Users then see "Token has expired or is invalid". The app should offer to send a new link. If this proves common, Supabase's documented alternative is a typed code from the email.
- **Email templates.** Keep the default `{{ .ConfirmationURL }}` templates. The `token_hash` templates in Supabase's password guide are for server-side apps, and this app has no such endpoint.

## 2. Flutter integration

Planned for 5B:

```dart
await Supabase.initialize(
  url: supabaseUrl,
  publishableKey: supabasePublishableKey,
  authOptions: const FlutterAuthClientOptions(
    authFlowType: AuthFlowType.pkce,
  ),
);
```

- Use `publishableKey`. `anonKey` is deprecated.
- Validate `SUPABASE_URL` the way `parseApiBaseUrl` validates the API address, but HTTPS only.
- If the settings are missing, show "Sign-in is not configured" instead of crashing, so `flutter test` and the shell still work without a project.
- Send the API the current access token as `Authorization: Bearer <token>`, and never log it.
- Change the test `account offers no sign-in or payment controls`, because the Account screen will now have sign-in controls. The checks for payment wording stay.

**Session storage.** By default the SDK stores the session in `shared_preferences` on Android and browser storage on the web. Neither is encrypted storage, and a stolen refresh token can keep a session alive.

- 5B keeps the default and sets `android:allowBackup="false"`, so Android's cloud backup doesn't copy the session.
- Before the pilot, decide whether to supply encrypted storage. The package documents a custom `LocalStorage` for this, with `flutter_secure_storage` as its example.

## 3. API verification

### Confirm the project's signing keys first

Don't choose the verifier until these checks are done on the real project. Supabase's own sources disagree on which algorithm new projects use, RS256 or ES256, so don't assume either.

1. Open the project's **JWT signing keys** page and note the state and algorithm of the current key.
2. Open `https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json`. It holds public keys only, and it is empty if the project doesn't use asymmetric keys.
3. In 5C, read the header and claims of one real token from a test account, using a local script that doesn't print the token. Confirm `alg`, `kid`, `iss` and `aud`. **This only reads the token and says nothing about whether it is genuine.**

| Result | Verifier |
| --- | --- |
| JWKS has a key, the current key is ES256 or RS256, and the token's `alg` and `kid` match | **Option A, the default:** local JWKS verification |
| JWKS is empty, or the current key is HS256 or the legacy secret | Migrate the project to asymmetric signing keys, which Supabase documents as possible without downtime, then use Option A |
| Migration isn't possible | **Option B:** ask Supabase Auth to check each token |

**Not an option: the shared JWT secret.** Supabase strongly recommends against verifying with it, because anyone holding it can forge tokens for any user.

### Option A: JWKS

The API would have one new setting, `VELORAUG_SUPABASE_URL`, and derive the rest:

| Value | Derived as |
| --- | --- |
| Issuer | `<url>/auth/v1`, compared exactly. A custom Supabase domain would change it |
| JWKS address | `<issuer>/.well-known/jwks.json` |
| Audience | The fixed value `authenticated` |
| Allowed algorithms | A fixed list in the code containing **only the algorithm confirmed above**. HS256 and `none` are never allowed |

Illustrative only, not final code:

```python
header = jwt.get_unverified_header(token)        # only to reject a bad alg early
if header["alg"] not in ALLOWED_ALGORITHMS:
    raise InvalidToken

signing_key = jwks_client.get_signing_key_from_jwt(token).key
claims = jwt.decode(                             # this is the verification
    token,
    signing_key,
    algorithms=ALLOWED_ALGORITHMS,
    audience="authenticated",
    issuer=issuer,
    options={
        "require": ["exp", "iat", "iss", "aud", "sub"],
        "strict_aud": True,
    },
)
user_id = UUID(claims["sub"])
if claims.get("role") != "authenticated" or claims.get("is_anonymous") is True:
    raise InvalidToken
```

| Check | How |
| --- | --- |
| Signature | `jwt.decode`, using a key from this project's JWKS only. Key addresses inside a token are never followed |
| Algorithm | The fixed list. It never comes from the token or from settings |
| Issuer, audience, expiry | `issuer`, `audience` and `exp`. `require` is needed because PyJWT only checks some claims if they are present |
| User identity | `sub` must be a UUID. `role` must be `authenticated`, and anonymous users are refused |

**Never use `verify_signature: False`, and never treat decoding as verification.** `user_metadata` is user-editable, so it must never decide access.

Other rules:

- Use a plain `def` FastAPI dependency, because `PyJWKClient` makes blocking network calls. FastAPI runs those in a thread pool.
- `PyJWKClient` settings: `timeout=5` and the default `lifespan=300`. Supabase asks apps not to cache keys beyond its 10-minute window, and to wait at least 20 minutes after creating a standby key or revoking a used one.
- Unknown `kid` values trigger a key refresh, so use a PyJWT version with `cooldown_duration`, so that invented `kid` values can't force constant fetching. Confirm this when pinning the version.
- Pin `PyJWT[crypto]`, because ES256 and RS256 need `cryptography`. Check that it builds for ARM64 in Milestone 10.

| Situation | Response |
| --- | --- |
| No header, wrong scheme, or any invalid token | `401` with `WWW-Authenticate: Bearer`. The body doesn't say which check failed |
| Keys can't be fetched, or the URL isn't set in development | `503`, and access is refused |
| `VELORAUG_ENVIRONMENT=production` without the URL | The API refuses to start |

`/health` and `/api/v1` stay public, and 5C adds `GET /api/v1/me`, which returns only the verified user ID. CORS must add `allow_headers=["Authorization"]`, because that header makes browsers send a preflight. Methods stay `GET`, and credentials stay off.

### Option B: Supabase Auth check

Use this only if the project can't use asymmetric keys. The API sends `GET <url>/auth/v1/user` with the publishable key as `apikey` and the user's token as `Authorization: Bearer`. A `200` means valid. A `401` or `403` from Supabase becomes `401`, and a timeout or `5xx` becomes `503`.

This adds one public setting, `VELORAUG_SUPABASE_PUBLISHABLE_KEY`, and still needs no secret. The cost is a network call per request, which Supabase warns can be slow, and sign-in depends on Supabase being reachable.

## 4. Revocation limits

- Sign-out removes the session and its refresh token, and clears the device.
- **An access token that already exists stays valid until `exp`.** Supabase states this, and the default lifetime is 1 hour. Local JWKS verification can't see a sign-out, so the API will accept that token until then.
- This is acceptable for reading a user ID. Later, for sensitive actions such as granting playback or payment changes, Milestones 8 and 9 should consider a shorter token lifetime or a live check with Supabase Auth. Don't add that now.

## 5. `profiles` table

**Draft only, and never run.** 5B must test it. Grants and policies are defined together because they do different jobs: grants decide what a role may do at all, and policies decide which rows it applies to.

This also has to be explicit because of a change Supabase enforced on all projects on 30 October 2026: new `public` tables get no automatic Data API access.

```sql
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (
    display_name is null or char_length(display_name) between 1 and 80
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Start from nothing, whatever the project's defaults are.
revoke all on table public.profiles from public, anon, authenticated, service_role;
grant select on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;

create policy "profiles_select_own" on public.profiles
  for select to authenticated
  using ((select auth.uid()) is not null and id = (select auth.uid()));

create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using ((select auth.uid()) is not null and id = (select auth.uid()))
  with check ((select auth.uid()) is not null and id = (select auth.uid()));

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

-- Stores the ID only. Sign-up metadata is user-controlled.
create function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

revoke execute on function public.set_profile_updated_at()
  from public, anon, authenticated, service_role;
revoke execute on function public.handle_new_user()
  from public, anon, authenticated, service_role;

-- Accounts created before this migration.
insert into public.profiles (id)
select id from auth.users
on conflict (id) do nothing;
```

| Rule | What enforces it |
| --- | --- |
| Read only your own row | The select policy |
| Update only your own row | The update policy, with `using` for the old row and `with check` for the new one |
| Change only `display_name` | The column-level grant. Policies choose rows, not columns, so this is what stops changes to `id`, `created_at` and `updated_at` |
| No creating or deleting rows directly | No insert or delete grant. The trigger creates rows, and deleting the user removes them through the foreign key |
| No self-granted privileges | There is no role or privilege column, so nothing can be escalated |
| No signed-out access | No grants to `anon` |

Supabase calls column privileges an advanced feature it doesn't recommend for most users. They are used here because the requirement is exactly column-level, and the table is small. `select *` still works, because the select grant covers the whole table.

**A failing trigger can block all sign-ups,** as Supabase warns. Keeping it to one insert with `on conflict do nothing` reduces that risk, and 5B must test sign-up after applying it.

## 6. Migration workflow

**Location:** `supabase/` at the repository root, created in 5B. Migrations are tracked in Git. `.supabase/` and `supabase/.temp/` are already ignored.

**CLI:** run a pinned version through `npx`, for example `npx --yes supabase@<exact version> <command>`. Scoop isn't installed here, Node 24 meets the Node 20 minimum, and this adds no `package.json` to the repository.

```powershell
npx --yes supabase@<version> init
npx --yes supabase@<version> login
npx --yes supabase@<version> projects list
npx --yes supabase@<version> link --project-ref <VeloraUG dev ref>
npx --yes supabase@<version> migration new create_profiles
# Add the reviewed SQL to the new file, then:
npx --yes supabase@<version> migration list --linked
npx --yes supabase@<version> db push --linked --dry-run
# Read the output. Apply only after confirming the project and the file list:
npx --yes supabase@<version> db push --linked
npx --yes supabase@<version> migration list --linked
```

Rules:

- **Never run `supabase db reset --linked` or `--db-url`.** It drops all user-created objects in the remote database. There is no reason to reset anything hosted.
- **Don't change the schema in the dashboard.** It bypasses migration history, and later pushes fail.
- **Don't edit an applied migration.** Fix mistakes with a new one.
- **Check the project reference before every push,** because the owner has other work on this machine. Never link a Supabase project used by `C:\Users\Wilsoft\velora`, or any other unrelated one.
- **Don't run `supabase config push` or use `--include-seed`.** Hosted Auth settings are set by hand from the [table below](#7-redirect-configuration), and no seed data is planned.
- **Keep credentials out of the commands.** Let the CLI prompt for the database password. The owner runs `link` and `push`, so the password isn't typed into a tool session.

**Check the target flag.** The CLI reference lists `--linked` for `db push`, while Supabase's migrations guide shows `--remote`. Confirm with `--help` on the pinned version before the first push.

`supabase start` needs Docker and runs the full stack, which is heavy on this machine with about 6 GB of RAM. It is optional. The new development project has no data to lose, so the dry run plus the [5B tests](#acceptance-criteria-for-5b) are the planned check.

## 7. Redirect configuration

Set these under **Authentication > URL Configuration**. Use exact values, with no wildcards. They must match the code character for character. Supabase warns that extra slashes break Flutter deep links.

| Project | Site URL | Additional Redirect URLs |
| --- | --- | --- |
| **Development** | `http://localhost:8765/` | `http://localhost:8765/` and `veloraug://auth-callback` |
| **Production**, later | `https://<production web host>/` | `https://<production web host>/` and the production Android callback |

Localhost must not be on the production list. Confirmation and recovery use the same callback, and the SDK tells them apart by the event it fires.

```dart
final authCallback = kIsWeb
    ? '${Uri.base.origin}/'
    : 'veloraug://auth-callback';
```

On the web this follows the address the app is running from, so no extra setting is needed. Supabase still refuses any address that isn't on the list above.

**Web.** The port must be 8765, and the host must be `localhost`, because `127.0.0.1` is a different browser storage area and would lose the verifier.

**`flutter run -d chrome` won't work for these tests.** It starts Chrome with a temporary profile, so sessions are lost between runs, and a link opened in your normal browser can't find the verifier. Use this instead, then open `http://localhost:8765/` in your normal Chrome:

```powershell
flutter run -d web-server --web-hostname localhost --web-port 8765 "--dart-define-from-file=dart_defines.local.json"
```

**Android.** In 5B, add this inside the `.MainActivity` activity in the main manifest. The `flutter_deeplinking_enabled` line is required by `app_links`, which the SDK uses:

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="veloraug" android:host="auth-callback" />
</intent-filter>
```

Limits:

- The email must be opened **on the phone**. A link opened on the computer can't reach the app.
- Another app could register the same custom scheme. PKCE limits the harm, because a stolen code is useless without the verifier.
- Phone browsers may handle the redirect into the app differently. 5B tests one phone only, so it can't show that every browser works.
- An HTTPS App Link would be stronger, but it needs a domain and the final application ID. Revisit before the pilot.

## 8. Email delivery

**Supabase's default email service is for development only, and production delivery isn't promised.**

| Default service limit | Effect here |
| --- | --- |
| Only sends to addresses in the project's team | Other people's sign-ups fail until custom SMTP is set up |
| 2 messages per hour, which may change without notice | Testing has to be paced. Each sign-up, resend and reset uses one |
| No delivery or uptime guarantee | A missing email doesn't prove the code is wrong |

**5B can use the default service** with one team address, in a planned order. For the second test user, the owner can add an account in the dashboard, confirmed by hand, because the two-user test doesn't depend on email.

**Before real users,** custom SMTP is required. That means an email provider, its host, port, username and password, and a sender address. Those credentials go in the Supabase dashboard only, never in this repository. Supabase then starts at 30 messages per hour, which can be raised. In practice a sender domain you control is needed, and none is recorded for this project, so [that is an open question](#information-needed-before-5b).

Also expect 30 requests per 5 minutes per IP address on sign-up and recovery endpoints, which a shared network could reach.

## 9. Android network rules

The main manifest has no `INTERNET` permission, because only debug and profile builds have needed it. Without it, a release build can't reach Supabase.

In 5B, add this to `android/app/src/main/AndroidManifest.xml`, directly inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Must not change:

- `networkSecurityConfig` stays in `src/debug/` only.
- Don't add `usesCleartextTraffic` anywhere.
- The release manifest gets the permission only, so HTTPS works and plain HTTP stays blocked by default.

A release build can't use `http://127.0.0.1:8000`, which is correct. So **API calls from a release build can't be tested until an HTTPS API exists**, in Milestone 10. Release sign-in can be tested in 5B, because Supabase uses HTTPS.

## Configuration

**Nothing reads these settings yet.** Both example files are tracked, and the real copies are ignored. `git check-ignore` confirmed that `dart_defines.json`, `dart_defines.local.json`, `dart_defines.prod.json`, `.env` and `.env.local` are ignored, and that `dart_defines.example.json` and `.env.example` are not. No ignore rule needed changing.

### Flutter: [`apps/client/dart_defines.example.json`](../apps/client/dart_defines.example.json)

Copy it to `apps/client/dart_defines.local.json`, and pass it with `--dart-define-from-file`. All three values are public, and anyone can read them from a built app.

| Variable | Purpose | Source | Destination |
| --- | --- | --- | --- |
| `API_BASE_URL` | Address of the FastAPI service | `http://127.0.0.1:8000` locally, and the HTTPS address later | Local file, and Cloudflare Pages build settings later |
| `SUPABASE_URL` | Address of the Supabase project | Project URL in the dashboard | Same |
| `SUPABASE_PUBLISHABLE_KEY` | Identifies the app to Supabase. Row-level security limits what it can reach | The `sb_publishable_...` key under **API Keys** | Same |

Never use the `sb_secret_...` or `service_role` key here.

### API: [`services/api/.env.example`](../services/api/.env.example)

| Variable | Purpose | Source | Destination |
| --- | --- | --- | --- |
| `VELORAUG_SUPABASE_URL` | Builds the issuer and JWKS address | Project URL in the dashboard | See below |

It is public, not secret. The secret key, the database password and the JWT secret are **not** needed. `VELORAUG_SUPABASE_PUBLISHABLE_KEY` is added only under [Option B](#option-b-supabase-auth-check).

### Proposed `.env` handling, for approval in 5C

The Python app stays as it is: no `env_file`, and the test showing `.env` is ignored stays valid.

| How the API runs | How the setting reaches it |
| --- | --- |
| Docker Compose | Add this to `infra/compose.local.yaml`, so Compose reads the file, not Python: `env_file: [{path: ../services/api/.env, required: false}]` |
| Directly with Python | `$env:VELORAUG_SUPABASE_URL = "https://<project-ref>.supabase.co"` in that terminal |

The `.dockerignore` allowlist already keeps `.env` out of the image.

## Owner setup

Nothing here is done, and these steps are for **before 5B**. Don't paste any key or password into a chat.

1. **Create a new Supabase project** just for VeloraUG development. Check how many active projects your plan allows. Don't reuse an existing project.
2. **During creation:** save the database password in a password manager, leave the Data API on, and leave "Automatically expose new tables" **off**.
3. **Under Authentication settings:** keep email sign-in and **Confirm email** on, and keep **anonymous sign-ins** off.
4. **Set the [redirect values](#7-redirect-configuration)** for development.
5. **Check signing keys**, using [the first two checks](#confirm-the-projects-signing-keys-first), and tell me the algorithm and whether JWKS lists a key.
6. **Create the local Flutter file:** copy `apps/client/dart_defines.example.json` to `apps/client/dart_defines.local.json`, and fill in the URL and publishable key.
7. **Choose test accounts:** one team email address you can open on both the computer and the phone, plus a second address for the second user.

## Information needed before 5B

| Question | Why it matters |
| --- | --- |
| Signing key algorithm, and whether JWKS lists a key | Decides the verifier and the allowed algorithm |
| Project reference | Confirms the right project before any push. It is not secret |
| Project region | Can't easily be changed later, and should be near your users and the Oracle server. The Oracle region isn't recorded in this repository |
| Is `veloraug://auth-callback` acceptable? | It is written into the manifest and the Supabase settings |
| Is display name the right first profile field? | The table adds only what is agreed |
| Do you run `link` and `push` yourself? | The plan assumes yes, so your database password stays with you |

Needed before real users, but not before 5B: the production web address, the production Android application ID, a sender domain and SMTP provider, a production Supabase project, and the session storage decision.

## Acceptance criteria for 5B

Each item needs its evidence recorded, and manual results must be labelled as user-reported, as in earlier reports. **Web** means the `web-server` command above, in a normal Chrome profile. **Android** means a real phone.

**Accounts, on web and Android:**

- [ ] Sign up shows "check your email", and no session exists until the email is confirmed
- [ ] The confirmation link returns to the app and the user is signed in or can sign in
- [ ] A wrong password shows the generic message
- [ ] A correct password signs in
- [ ] The session survives a full close and reopen, and a browser reload
- [ ] Password reset from the emailed link opens the new-password screen, including when the app wasn't already running on Android
- [ ] The old password then fails, and the new one works
- [ ] A link opened on another device or browser shows the planned helpful message and doesn't crash
- [ ] An expired or already-used link shows an error, with an offer to send a new one
- [ ] Reset for an unknown address shows the same message as for a known one

**Sign-out:**

- [ ] The app shows signed-out, and stays signed-out after reopening
- [ ] The session no longer appears in local storage
- [ ] The old refresh token can no longer be used
- [ ] Sign-out with no network was tried, and the result recorded. The SDK's behaviour here wasn't confirmed from its docs. If it keeps the session, the app must handle that, and the plan gets updated

**Profiles, using real tokens and the publishable key, never a secret key:**

- [ ] A new sign-up gets exactly one profile row, and sign-up still works with the trigger in place
- [ ] A signed-out request reads nothing and writes nothing
- [ ] User A reads their own row, and sees no row for user B, including when asking for B's ID directly
- [ ] User A updating B's row changes nothing, and B's row is confirmed unchanged as B
- [ ] User A can change their own `display_name`
- [ ] User A changing their own `id`, `created_at` or `updated_at` is refused
- [ ] Insert and delete on `profiles` are refused
- [ ] Sign-up metadata doesn't reach the row
- [ ] Deleting a test user removes their profile
- [ ] A read-only query of the hosted project confirms that RLS is on, and that the grants match the migration

**Android and repository:**

- [ ] The merged release manifest has `INTERNET`, no `networkSecurityConfig` and no `usesCleartextTraffic`
- [ ] The merged debug manifest keeps its loopback rule, and the Step 4C phone check still passes
- [ ] A release build can sign in on a phone over HTTPS
- [ ] `allowBackup` is `false`
- [ ] The migration is in Git, and `migration list` shows local and remote matching
- [ ] No real configuration or credential is tracked, and a search of tracked files finds no key
- [ ] Format, analyze, tests and web and APK builds pass

## Acceptance criteria for 5C

Automated tests use a locally generated key pair and a local JWKS, so they need no network or real project.

**A token must be rejected with `401` when it is:**

- [ ] Missing, or sent with a scheme other than `Bearer`
- [ ] Malformed
- [ ] Expired
- [ ] Tampered with, in the payload or the signature
- [ ] Signed with `alg: none`
- [ ] Signed with HS256 using the public key as the secret
- [ ] Signed by a different key that claims the right issuer and `kid`
- [ ] From another project: a valid signature and another project's issuer
- [ ] Carrying the wrong audience, including `anon`
- [ ] Missing `exp`, `iat`, `iss`, `aud` or `sub`, or with a `sub` that isn't a UUID
- [ ] Carrying a `role` other than `authenticated`, or `is_anonymous: true`
- [ ] Using an unknown `kid`, without refetching the keys on every attempt

**Other automated checks:**

- [ ] A valid token returns `200` from `/api/v1/me`, with the `sub` from the token
- [ ] Unreachable keys return `503`, not `200` or `401`
- [ ] `/health` and `/api/v1` stay public
- [ ] A preflight from `http://localhost:8765` allows `Authorization`, and other origins are still refused
- [ ] No token appears in logs or error responses
- [ ] The settings contain no secret, and the API starts without one
- [ ] `ruff` and `pytest` pass, and the Docker image builds and runs with a healthy status

**Against the real project:**

- [ ] The signing check results are recorded, and the verifier matches them
- [ ] Web: signing in then calling `/api/v1/me` returns the right user, through real CORS
- [ ] Android: the same call works over `adb reverse`
- [ ] Signed out in the app: the app sends no token, and `/api/v1/me` returns `401`
- [ ] A real token more than its lifetime old is refused as expired
- [ ] A real token with one changed character is refused
- [ ] A token captured before sign-out is still accepted until `exp`, and this is recorded as [the known limit](#4-revocation-limits), not a failure

A real token from another project isn't required, because the local test covers it, and another project must not be touched to get one. It can be added only if the owner creates a throwaway project for it.

## Still unconfirmed

| Item | Resolved by |
| --- | --- |
| This project's signing algorithm | Owner setup |
| SDK behaviour on sign-out with no network | 5B test |
| Newest-link-only behaviour | 5B test |
| Password recovery event when the app starts from the link | 5B test |
| Phone browsers following the custom-scheme redirect | 5B test, on one phone only |
| The draft SQL, including revoked function execute rights and the trigger on `auth.users` | 5B dry run and tests |
| `cooldown_duration` in the pinned PyJWT version | 5C |
| Exact dashboard labels | Owner setup |

## Sources

Read on 3 November 2026.

**Tokens and keys:** [JWTs](https://supabase.com/docs/guides/auth/jwts), [JWT claims](https://supabase.com/docs/guides/auth/jwt-fields), [signing keys](https://supabase.com/docs/guides/auth/signing-keys), [API keys](https://supabase.com/docs/guides/api/api-keys), [PyJWT usage](https://pyjwt.readthedocs.io/en/stable/usage.html), [PyJWT API](https://pyjwt.readthedocs.io/en/stable/api.html), and for conflicting information on the default algorithm, the [signing keys announcement](https://supabase.com/blog/jwt-signing-keys) and [changelog](https://supabase.com/changelog/29289-supabase-auth-asymmetric-keys-support-in-2025).

**Account flows:** [password auth](https://supabase.com/docs/guides/auth/passwords), [PKCE flow](https://supabase.com/docs/guides/auth/sessions/pkce-flow), [sessions](https://supabase.com/docs/guides/auth/sessions), [sign-out](https://supabase.com/docs/guides/auth/signout), [redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls), [email templates](https://supabase.com/docs/guides/auth/auth-email-templates), [custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp), [rate limits](https://supabase.com/docs/guides/auth/rate-limits), [general configuration](https://supabase.com/docs/guides/auth/general-configuration).

**Flutter and Android:** [Dart initialization](https://supabase.com/docs/reference/dart/initializing), [`supabase_flutter`](https://pub.dev/packages/supabase_flutter), [its client options](https://pub.dev/documentation/supabase_flutter/latest/supabase_flutter/FlutterAuthClientOptions/FlutterAuthClientOptions.html), the SDK's [`signUp`](https://pub.dev/documentation/gotrue/latest/gotrue/GoTrueClient/signUp.html), [`resetPasswordForEmail`](https://pub.dev/documentation/gotrue/latest/gotrue/GoTrueClient/resetPasswordForEmail.html), [`exchangeCodeForSession`](https://pub.dev/documentation/gotrue/latest/gotrue/GoTrueClient/exchangeCodeForSession.html) and [`signOut`](https://pub.dev/documentation/gotrue/latest/gotrue/GoTrueClient/signOut.html), [native deep linking](https://supabase.com/docs/guides/auth/native-mobile-deep-linking?platform=flutter&os=android), [`app_links` Android setup](https://github.com/llfbandit/app_links/blob/main/doc/README_android.md), [Flutter networking](https://docs.flutter.dev/data-and-backend/networking).

The password auth page says Dart defaults to the implicit flow. The current `FlutterAuthClientOptions` source says `AuthFlowType.pkce`. This plan follows the source, and sets the value explicitly.

**Database:** [row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security), [column-level security](https://supabase.com/docs/guides/database/postgres/column-level-security), [managing user data](https://supabase.com/docs/guides/auth/managing-user-data), [public schema grants change](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically), [database migrations](https://supabase.com/docs/guides/deployment/database-migrations), [`db push`](https://supabase.com/docs/reference/cli/supabase-db-push), [`db reset`](https://supabase.com/docs/reference/cli/supabase-db-reset), [CLI installation](https://supabase.com/docs/guides/local-development/cli/getting-started).
