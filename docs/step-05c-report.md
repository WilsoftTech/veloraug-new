# Step 5C report: sign-in pages

Date: 5 November 2026. This follows the [Neon plan](step-05a-neon-plan.md#5c-auth-pages) and the [Step 5B report](step-05b-report.md). **Step 5C is not complete.** The pages are built and pass local checks, but they haven't been deployed, and the real flows need the owner's mailboxes. No authentication behaviour in the Flutter app or Neon settings changed, and nothing was pushed.

## What changed

All in [`apps/auth_pages/`](../apps/auth_pages/README.md).

| Item | Change |
| --- | --- |
| Error messages | Written by the pages, from the server's raw code. "validation_failed" no longer appears, and server text is never shown |
| Timed-out request | A clear page with **Back to VeloraUG**, which returns an OAuth error to the app so that it stops waiting. It appears when the page loads after `exp`, or when the server reports `invalid_signature` |
| Email code | **Send a new code**, and a hint for an address that may already have an account. The hint always shows, so it reveals nothing |
| Unverified account | Signing in with the right password now sends a code and opens the code page |
| Password reset | Complete: request, code and new password, send a new code, then sign in. The wording doesn't depend on whether the address has an account |
| Consent | Permissions in plain words, and a warning when the app runs on this computer, as Neon's guide requires |

**Why the unverified path matters.** Once a request expires, every call fails, even with a correct code. A person who took too long over their email would be left with an unverified account. They can now sign in again from the app, and confirm their email from there.

**Differences from the plan.** `checkVerificationOtp` isn't used, because `resetPassword` checks the code itself. The timed-out page returns `error=login_required`, and the Flutter proof shows that as a refused sign-in. Step 5D should word it properly.

## Tested

| Check | Result |
|---|---|
| `npm test` | 22 passed. They run the SDK's real error mapping, so an SDK upgrade that moves the raw code fails them |
| Build | Succeeded, with the real Auth URL |
| Real SDK against Neon, using only failures that can't create an account | Each gave the expected result, listed below |
| `wrangler pages dev`, local only, with the real `_headers` | All seven addresses returned `200` with `frame-ancestors 'none'`, including `assetlinks.json` |
| Six pages at 360 pixels wide, in headless Chrome | No sideways overflow, and every button and field is at least 48 pixels tall |
| Timed-out page | Link is `http://localhost:8765/auth.html?error=login_required&state=abc`. With `redirect_uri` set to another site, that address doesn't appear on the page |
| Search of the build | No `client_secret`, `postgresql://`, `npg_`, `neondb_owner`, `napi_` or `validation_failed:` |

| Real request | Server's code | The page says |
|---|---|---|
| Sign in, unknown address | `INVALID_EMAIL_OR_PASSWORD` | That email or password is incorrect. |
| Sign up, short password | `PASSWORD_TOO_SHORT` | Use a password of at least 8 characters. |
| Sign up, invalid email | `VALIDATION_ERROR` | Check what you entered and try again. |
| Verify, wrong code | `INVALID_OTP` | That code is incorrect or has expired. Check it, or send a new one. |
| Reset, wrong code, unknown address | `INVALID_OTP` | Same |
| Tampered signed request | `invalid_signature` | Opens the timed-out page |

Interaction wasn't tested in a browser. The forms were rendered, and their requests were made separately through the SDK, so the first real click-through is the owner's.

## Acceptance criteria

| Criterion | State |
| --- | --- |
| Sign-up sends a code, and no session exists until the code is entered | **Needs the owner** |
| A wrong or expired code shows an error, with an offer to send a new one | Wrong code checked against the server. Expired code checked with a test only. **Needs the owner** |
| A wrong password and an unknown address show the same message | **Met.** The server sends the same code for both: the owner saw it for a real account on the previous pages, and a probe confirmed it for an unknown address |
| Reset by code: the old password fails, and the new one works | **Needs the owner** |
| Consent shows client, callback host, scopes and resource, and denying returns an error to the app | Display rendered. **Denying needs the owner** |
| The second sign-in doesn't ask for consent again | Step 5B timings fit this. **Needs the owner to confirm** |
| An expired signed query gives a clear message and a way back to the app | Page rendered. **The return needs the owner** |
| `frame-ancestors 'none'` is present as a response header | Met locally. **The checker confirms it after deployment** |
| `assetlinks.json` is served with the right content | Same |
| A search of the built site finds no secret, and it has no database address | **Met** |

## Not addressed

| Item | State |
| --- | --- |
| Visual approval | Still pending from [Step 3B](step-03b-report.md). The new error style uses the existing danger tokens |
| Why the code for an existing address is refused | Not established. The pages now point that person to sign-in and reset |
| The first sign-up error's cause | [Still not settled](step-05b-report.md#sign-up-error-validation_failed) |
| Custom email | Still Neon's shared service, which isn't for real users |
| Response timing and email content for an existing address | Not compared |
| Rate limits on sending codes | Not tested, to avoid using up the shared email service |
| Screen readers | Not tested. Errors use `role="alert"` |

## Deploy and test

Deploy, then check:

```powershell
cd C:\Users\Wilsoft\veloraug\apps\auth_pages
npm run build
npx --yes wrangler@4.157.0 pages deploy dist --project-name veloraug-auth-dev --branch main

cd ..\..
python infra\neon\check_step05b.py
```

The app doesn't need reinstalling. On the phone, on the Account screen under Sign-in proof, press **End browser session** and tap the sign-out button, then:

1. **Deny.** Press **Sign in**, choose **Create an account**, and use a mailbox with no account. Enter a wrong code and note the message, press **Send a new code**, then enter the new code. On the consent page, press **Deny**, and note what the panel shows. No session should exist before the correct code.
2. **Allow.** Press **Sign in**. If the form appears, sign in. Press **Allow**. Then press **Sign in** again, and note that consent isn't asked again.
3. **Reset.** Sign out as above, then press **Sign in**, choose **Forgot password**, and use that account's address. Enter a wrong code and note the message, then the real code with a new password. Sign in with the old password, which should fail, then the new one.
4. **Unverified account.** Sign out, press **Sign in**, and create an account with a second mailbox. **Don't enter the code.** Close the tab with Back. Press **Sign in**, and sign in with that address and password. The code page should open with a new code. Enter it and finish.
5. **Timed out.** Sign out, press **Sign in**, and leave the form open for more than 10 minutes. Try to sign in. The timed-out page should appear. Press **Back to VeloraUG**, and note what the panel shows.
