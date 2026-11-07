# Step 5C report: sign-in pages

Date: 5 November 2026. This follows the [Neon plan](step-05a-neon-plan.md#5c-auth-pages) and the [Step 5B report](step-05b-report.md). **Step 5C is complete.** The owner deployed the pages on 5 November, the check script passed, and every [acceptance criterion](#acceptance-criteria) is met, with the flows user-reported on one phone from 5 to 7 November. No authentication behaviour in the Flutter app or Neon settings changed, and nothing was pushed.

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
| Sign-up sends a code, and no session exists until the code is entered | **Met,** user-reported. After a sign-up with no code entered, signing in with the right password opened the code page instead of signing in |
| A wrong or expired code shows an error, with an offer to send a new one | **Met,** user-reported. A wrong code showed the error on sign-up and reset, and a code from **Send a new code** worked. An expired code was checked with a test only |
| A wrong password and an unknown address show the same message | **Met.** The server sends the same code for both: the owner saw it for a real account on the previous pages, and a probe confirmed it for an unknown address |
| Reset by code: the old password fails, and the new one works | **Met,** user-reported. The old password showed "That email or password is incorrect.", and the new one signed in |
| Consent shows client, callback host, scopes and resource, and denying returns an error to the app | **Denying is met:** the app received `access_denied` and stayed signed out. **The display is met,** user-reported: the owner confirmed it names the app, the return address, the permissions and the API |
| The second sign-in doesn't ask for consent again | **Met by timing, not seen directly.** Sign-ins straight after another took 1.4, 2.0 and 1.2 seconds on the deployed pages, too short to press **Allow**. See the [phone run](#phone-run-on-the-deployed-pages) |
| An expired signed query gives a clear message and a way back to the app | **Met.** The owner read the timed-out message and found it clear. The app received `login_required`, which only that page's link sends |
| `frame-ancestors 'none'` is present as a response header | **Met.** The check script found it on the deployed `/login`, `/consent` and `/auth/callback/android` |
| `assetlinks.json` is served with the right content | **Met.** The check script confirmed the package ID and certificate on the deployed site, and Google's Digital Asset Links service and the phone both confirm the link |
| A search of the built site finds no secret, and it has no database address | **Met** |

## Phone run on the deployed pages

The owner's panel text from 5 November, user-reported. It came with no notes, so anything about what appeared on screen is inferred.

| Panel result | Reading |
| --- | --- |
| Sign-in after 5.0 seconds, then refresh with rotation | Worked. Too short to type a password, so a browser session was probably still valid |
| Reuse of the old refresh token: `400 invalid_grant`, then refresh: `400 invalid_grant` | Reuse also ended the current token, as on the web client |
| Revoke: `400`, then refresh: `400 invalid_grant` | **Not a revoke result.** That token had already been ended by the reuse test. Refusal after revoke on the Android client is still not shown |
| End browser session, then sign-in after 36.3 seconds | Worked. Long enough for the form, but whether it appeared and what was pressed aren't recorded |
| Sign-in after 1.4 seconds | Worked, with no time to press **Allow** |
| End browser session, then `CANCELED` after 1 minute 22 seconds | The tab closed with no callback. Pressing Back would explain it, but that isn't confirmed |
| `login_required` after 19 minutes 10 seconds | The request expired after 10 minutes, and the timed-out page's link returned to the app. The panel shows this as a refusal, and Step 5D should word it properly |

**Not shown by this run:** Deny, wrong or new email codes, no session before the correct code, password reset, and the unverified account path. The panel has no `access_denied` line, so a Deny isn't recorded here.

**The owner's notes on the same day, user-reported:**

| Flow | Reported | Not reported |
| --- | --- | --- |
| Sign-up | A code reached a mailbox with no account. A wrong code showed "That code is incorrect or has expired. Check it, or send a new one." | A new code, the correct code, and Deny |
| Reset | A wrong code showed the same message | The password change, and signing in with the old and new passwords |
| Unverified account | A code reached the new mailbox, and "it opened", taken to mean the code page | Entering the code and finishing the sign-in |
| Timed out | The page explained that the sign-in had timed out, that requests last about 10 minutes, and how to return and confirm an email. The owner found it clear | Nothing |

### Second phone run on the deployed pages

The owner's panel text and notes from 7 November, user-reported. Which panel line belongs to which flow is inferred from timing.

| Panel result | Reading |
| --- | --- |
| `login_required` after 14 minutes 10 seconds | Another timed-out request, past the 10-minute limit |
| `access_denied` after 3 minutes 20 seconds | **Deny works.** The owner created an account with a new mailbox, then pressed **Deny**, and the app stayed signed out |
| Sign-in after 1 minute 5 seconds, then two after 2.0 and 1.2 seconds | The owner reports that signing in after the Deny showed the consent page again. That fits Neon's rules, since a denial stores no consent. The two quick sign-ins after that had no time for consent |
| End browser session, then sign-in after 7 minutes 52 seconds | Fits the reset: the owner reports the old password showed "That email or password is incorrect.", and the new one signed in |

**Owner's final notes, 7 November, user-reported.** Unverified account: after a sign-up with no code entered, signing in with the password opened the code page. **Send a new code**: the newest code worked. Consent page: it names the app, the address it returns to, the permissions and the API. No panel text came with these, so whether that sign-in ended in `code exchanged` isn't recorded.

## Not addressed

| Item | State |
| --- | --- |
| Visual approval | The owner approved the design on 5 November 2026: see [Step 3B](step-03b-report.md). The new error style uses the existing danger tokens |
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
