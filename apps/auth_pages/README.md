# Sign-in companion

A minimal Vite and React site using `@neon/auth`. Neon Auth redirects to these pages during sign-in, because it provides no default pages and has no Flutter SDK. See the [Neon plan](../../docs/step-05a-neon-plan.md#2-auth-pages).

**This is the Step 5B proof, not the finished pages.** Styling, password reset completion, resending codes and final wording come in Step 5C.

It holds no secrets. Everything here is public, including the Neon Auth URL, which is built into the pages. It never connects to the database.

| Address | Purpose |
| --- | --- |
| `/login`, `/sign-up`, `/consent` | The sign-in flow. Neon sends the signed request here |
| `/reset` | Requests a reset code, to test what the response reveals (gate G9) |
| `/sign-out` | Ends the Neon browser session, then returns to the app |
| `/auth/callback/android` | The Android App Link target. Android normally opens the app without showing it |
| `/.well-known/assetlinks.json` | Tells Android that `com.example.veloraug`, signed with this computer's debug certificate, may open those addresses |

## Check locally

```powershell
cd C:\Users\Wilsoft\veloraug\apps\auth_pages
npm ci
npm test
```

## Deploy to the development site

The owner runs these. The steps around them are in the [Step 5B report](../../docs/step-05b-report.md#what-you-need-to-do).

`npm run build` refuses to run until `.env.local` has the real Neon Auth URL of the `development` branch. `infra/neon/step-05b-configure.ps1 -Phase Branch` writes that file.

```powershell
npx --yes wrangler@4.157.0 login
npx --yes wrangler@4.157.0 pages project create veloraug-auth-dev --production-branch main
npm run build
npx --yes wrangler@4.157.0 pages deploy dist --project-name veloraug-auth-dev --branch main
```

**The address must be exactly `veloraug-auth-dev.pages.dev`.** `pages project create` prints it. If Cloudflare adds a suffix because the name is taken, stop, because the same address is in the Android manifest, the Neon settings and the Flutter settings.
