# Step 10A plan: passes and payments

Date: 19 November 2026. This plans Milestone 10 in the [roadmap](roadmap.md): prepaid **daily, weekly and monthly passes**, paid through Pesapal. It follows [the look ahead in the Milestone 9 plan](step-09a-vj-catalogue-plan.md#7-looking-ahead-to-milestone-10-passes). **Steps 10B to 10D were written and built on 19 November 2026 at the owner's request to implement Milestone 10, with this plan not yet approved.** Step 10E needs the owner and Pesapal's sandbox.

Facts about Pesapal come from its [API 3.0 pages](#sources), as read on this date.

> **Updated 21 November 2026: six-tier subscriptions and devices.** The owner approved a new catalogue, which replaces the day, week and month passes for sale, and added device limits. What is built, and what is still unverified, is in [Milestone 10 subscriptions](#milestone-10-subscriptions) below. The sections after it describe Step 10B as first built; where they disagree, the Milestone 10 section wins.

## Milestone 10 subscriptions

Built on branch `feature/milestone-10-subscriptions`, 21 November 2026. Not merged, not deployed, and not run against Neon, Cloudflare or Pesapal.

### The catalogue

| ID | Name | UGX | Days | Devices | Screens at once |
| --- | --- | ---: | ---: | ---: | ---: |
| `velora_start` | Velora Start | 6,000 | 7 | 1 | 1 |
| `velora_flex` | Velora Flex | 10,000 | 14 | 1 | 1 |
| `velora_prime` | Velora Prime (featured) | 18,000 | 30 | 1 | 1 |
| `velora_duo` | Velora Duo | 50,000 | 90 | 2 | 2 |
| `velora_pro` | Velora Pro | 90,000 | 180 | 2 | 2 |
| `velora_max` | Velora Max | 150,000 | 365 | 3 | 3 |

Every plan covers every published film and series. Durations are exact UTC intervals (`make_interval(days => n)`), not calendar months. Nothing renews by itself. The app shows only what the API sends: name, price, days, devices and screens.

`day`, `week` and `month` stay in `pass_plans`, marked `legacy` and off sale, so earlier payments and passes keep a valid plan. The database refuses to put a legacy pass back on sale.

### Decisions

| # | Decision | Why |
| --- | --- | --- |
| M1 | **Migration `0007`, forward only.** `0006` is untouched. The six tiers are seeded with `on conflict do nothing`, so re-running never overwrites an admin's price | Hosted branches are never downgraded |
| M2 | **Every payment and pass keeps a snapshot**: plan name, days, price, devices and screens at the time of purchase. A trigger refuses a new payment that doesn't match its plan as it is on sale, and a second trigger refuses any change to what a payment bought through the API's roles | A later price change can't touch what was bought, and an API bug can't charge a made-up price |
| M3 | **Passes queue, they don't merge.** A new pass starts when the last ends, whatever the tier, and each has its own start, end, plan and allowances. The pass running now decides the limits | Keeps the Step 10B rule that buying early never loses days, without adding two tiers' devices together |
| M4 | **A reversal ends its pass, and the passes queued behind it move up**, kept whole. Through the API's roles, only a pass that hasn't started can move | No paid time is stranded behind a gap |
| M5 | **A smaller plan doesn't delete devices.** Playback answers `409 device_limit` until the viewer removes devices in Account → My devices, so the viewer chooses which to keep | Deterministic, and the choice is the viewer's |
| M6 | **Devices are identified by a server-made secret.** On registering, the API makes an ID and a 32-byte random secret, shown to the device once and stored only as its SHA-256. The device sends `X-Velora-Device: <id>.<secret>`. No IMEI, serial number or advertising ID is read | A copied or made-up ID is useless without its secret; a database leak can't be replayed |
| M7 | **At most three devices and three streams per account, whatever the plan**, enforced in the API and again by database triggers, both under one per-account advisory lock. One device plays one thing at a time (a unique index) | Simultaneous requests can't pass the limit |
| M8 | **Device switching:** removing a device frees its place at once, but an account can register at most its plan's devices **plus three** in any 30 days (`429 device_switch_limit` beyond) | Allows a lost or broken phone to be replaced, without unlimited sharing |
| M9 | **Playback sessions.** With passes required, each grant names a random session ID (`"s"`), lasts at most 1 hour (and never past the pass), and the player sends a heartbeat every 60 seconds. A session not heard from for 3 minutes is over | A closed tab frees its stream, and a stolen grant dies with its session |
| M10 | **The media gateway asks the API about each session**, at most every 30 seconds per isolate, signed with the shared key under its own context (`veloraug-gateway-v1.`). The API answers yes or no and the pass's end, nothing else. If the API can't be reached, a session seen live in the last 2 minutes carries on; otherwise 503 | Removing a device, stopping a session, a reversal or an expired pass stops the video within about 30 seconds, not 6 hours |
| M11 | **Status codes:** 401 not signed in; 402 no running pass; 403 `device_required` (the app registers itself and retries once) or `device_revoked`; 409 `device_limit`, `stream_limit`, or the item isn't ready; 410 session ended; 429 too many requests or `device_switch_limit` | One meaning per code, with a machine-readable `code` where one status has several |
| M12 | **Checkout retries reuse the payment.** The same plan at the same price within 10 minutes answers the same Pesapal page (200) instead of a second order | A double tap or a retry never makes two orders |
| M13 | **Rate limits per account**, in memory: 6 checkouts per 10 minutes, 60 payment checks a minute, 10 device registrations an hour, 30 playback grants a minute. 429 with `Retry-After` | The pilot runs one API process. Cloudflare's rule in front is still to be added (11D) |
| M14 | **Audit events** go to the `veloraug.audit` logger as one JSON line each, with only an allow-listed set of fields: IDs, plan, amount and times. Never an email, phone, token, secret or grant | Useful history without leaking customer data |
| M15 | **Admins read billing and remove devices, never rewrite money.** The editor role can read payments, passes, devices and sessions, change a plan's price, sale and featured flags, and remove a device. Every plan change is written by a trigger to `plan_changes`. Contact details reach admin screens masked (`v***@example.com`) | History can't be changed from the admin screens |
| M16 | **Admins and passes-off stay as before**: no device registration or session, a 6-hour grant without `"s"` | Today's production viewing is unchanged while `VELORAUG_PASSES_REQUIRED` is off |

### New and changed routes

| Route | What |
| --- | --- |
| `GET /api/v1/passes/plans` | Adds `display_name`, `description`, `max_devices`, `max_streams`, `featured` |
| `GET /api/v1/me/pass` | Adds `current` and `queued`, each with its own plan, dates and allowances |
| `GET /api/v1/me/payments` | The viewer's last 20 payments, with Pesapal's confirmation code once paid |
| `GET`, `POST /api/v1/me/devices`; `PATCH`, `DELETE /api/v1/me/devices/{id}` | List with the plan's allowance and `over_limit`; register (201, or 200 if this device already is); rename; remove |
| `GET /api/v1/me/playback-sessions`; `DELETE …/{id}`; `POST …/{id}/heartbeat` | What is playing; stop one; keep one alive |
| `GET /api/v1/gateway/sessions/{id}` | The media gateway only, with `X-Velora-Gateway` |
| `PATCH /api/v1/admin/pass-plans/{id}` | Adds `for_sale` and `featured` (one featured plan at a time) |
| `GET /api/v1/admin/billing/metrics`, `/payments?state=`, `/subscribers`, `/users/{id}`, `/plan-changes`; `DELETE /api/v1/admin/billing/users/{id}/devices/{device}` | Admin → Subscriptions |

### Status

| Item | State |
| --- | --- |
| Migration `0007`, triggers, row-level security, grants | Built; upgrade, downgrade and re-upgrade pass on a local Postgres set up as Neon is; `check_database.py` passes every check, including five new ones |
| API: tiers, snapshots, queueing, reversal, devices, sessions, gateway check, rate limits, audit, admin billing | Built; 591 API tests pass, 34 of them new in `tests/test_subscriptions.py`, with Pesapal faked |
| Media gateway: session-bound grants | Built; 39 Worker tests pass, 11 new, with a signature vector shared with the API's tests |
| App: plan cards, Account (membership, devices, payments), player limits and heartbeat, Admin → Subscriptions | Built; 431 widget and unit tests pass with the API faked; the web release build compiles |
| Pesapal's sandbox with the new tiers | **Not run** |
| Migration `0007` on Neon | **Not run**. See the [run sheet](step-10e-runbook.md#migration-0007) |
| The Worker with `API_URL`, deployed | **Not deployed**. Reaching `api.veloraug.com` from the Worker is unverified |
| An Android build and a phone | **Not run** for this branch |
| `VELORAUG_PASSES_REQUIRED` | Off, and stays off until the 10E run sheet passes |

## Summary

- **A pass lets a signed-in viewer watch everything published, until it ends.** Three kinds: a day (24 hours), a week (7 days) and a month (30 days). **Prices are set by an admin** in Settings, in Uganda shillings. A pass with no price isn't for sale.
- **Paying happens on Pesapal's own page.** The app asks the API to start a payment, and opens Pesapal's page in a new tab on the web, or in the browser on Android. The viewer pays there by MTN or Airtel Money, or by card. The app never sees a phone PIN or a card number.
- **The API alone decides that a payment went through.** Neither the viewer's return from Pesapal nor Pesapal's notification says whether a payment succeeded. Each only makes the API ask Pesapal, with its own keys, for the payment's status. A pass is made only when Pesapal answers `COMPLETED` for the exact amount, in UGX.
- **Grants never outlive a pass.** A playback grant expires at whichever comes first: 6 hours from now, or the end of the viewer's current pass. The Worker doesn't change: it already refuses an expired grant on every chunk.
- **When a pass ends mid-film,** the player's renewal is refused with **402**, and it shows **"Your pass has ended"** with **Buy a pass**. The app never leaves the film to pay, so after paying, playback carries on from the same moment.
- **Passes are switched on by a setting, `VELORAUG_PASSES_REQUIRED`.** Off by default, so the Milestone 9 checks and any viewing before launch carry on as now. Admins never need a pass.

## Implementation sequence

| Step | Scope | Finished when |
| --- | --- | --- |
| **10A**, this step | This plan | The owner approves it |
| **10B** | Migration `0006_passes`. The Pesapal client. The pass routes: prices, checkout, a payment's status, Pesapal's return and notification. Grants capped at the pass's end, and 402 without one. Admin routes for prices. `register-ipn` | [10B criteria](#10b-api) pass |
| **10C** | The app: Passes on the Account tab, buying a pass, waiting for the payment, the player's "You need a pass" and "Your pass has ended", and pass prices in the admin Settings | [10C criteria](#10c-app) pass |
| **10D** | The run sheet for 10E, and the docs | Written |
| **10E** | With the owner, on Neon and Pesapal's sandbox: one pass bought, playback allowed, the pass ended, playback refused, and another pass bought from the player | [10E criteria](#10e-end-to-end) pass |

Not in Milestone 10: automatic renewal; pay per title; refunds from the app (done in Pesapal's dashboard); promotional codes and free trials; limits on devices; receipts by email; Pesapal's live account (needs the business's documents, and waits for [Check before launch](roadmap.md#check-before-launch)).

## Decisions

| # | Decision | Why |
| --- | --- | --- |
| 1 | Three passes: **day** (24 hours), **week** (7 days), **month** (30 days), each one catalogue-wide | The owner's direction in Milestone 9 |
| 2 | **Prices in whole Uganda shillings**, set by an admin, from UGX 500 to 10,000,000. No price means not for sale | Prices are still open. The owner can change them without a new release. UGX has no cents |
| 3 | **Pesapal API 3.0**, the sandbox until launch | Pesapal takes MTN and Airtel Money and cards in Uganda, on one hosted page. API 2.0 is deprecated |
| 4 | **Pesapal's page, never an embedded form.** Opened in a new tab on the web, and in the browser on Android | No payment details touch the app or the API. A new tab keeps the app, and the player, where they were |
| 5 | **Confirmation only from `GetTransactionStatus`**, asked by the API. The return and the notification only prompt it. A pass needs `status_code` 1 (`COMPLETED`), the payment's own reference, its exact amount and `UGX` | Anyone can call a return or notification address with made-up details. Pesapal's documentation says neither carries the status |
| 6 | Three ways a payment gets checked: **Pesapal's notification (IPN)**; **the app, every 3 seconds**, while the viewer is paying; and **opening the Account tab**, for the viewer's own unfinished payments of the last 24 hours | The notification needs an address Pesapal can reach, which this PC doesn't have until Milestone 11. The other two work anywhere, and cover a notification that never comes |
| 7 | A payment is `started`, then `pending` on Pesapal. It becomes **`completed`** with a pass, **`failed`**, **`reversed`** or **`abandoned`**. `failed` is checked again until 24 hours have passed, and then becomes `abandoned` | On Pesapal's page a viewer can fail with one method and then pay with another, under the same order |
| 8 | **A new pass starts when the viewer's last one ends**, or now if none is running | Buying early never loses days |
| 9 | **A reversed payment ends its pass at once** | Pesapal's `REVERSED` is money returned |
| 10 | Pesapal's return address is **the API's** `/api/v1/passes/return`, a short page: "Payment received. You can close this tab and go back to VeloraUG" | Pesapal says the return page shouldn't answer in JSON. The app is still open in the other tab |
| 11 | The notification address is `/api/v1/passes/ipn`, registered **as GET** once with `register-ipn`. It answers in the JSON Pesapal asks for, with status 200, or 500 if the check couldn't be done | Pesapal's documented reply |
| 12 | **Pesapal needs the viewer's email or phone.** The app sends the email the viewer signed in with. Without one, it asks for a phone number. They're stored only on that payment | Pesapal requires one of them on every order. Nothing more is asked |
| 13 | A grant expires at **`min(now + 6 hours, the current pass's end)`** | As planned in Milestone 9 |
| 14 | Without a pass, the grant route answers **402**, and the player shows **"You need a pass to watch"**, or **"Your pass has ended"** if it was playing, with **Buy a pass** | 402 is the status for "pay first", and keeps "not signed in" (401) apart |
| 15 | **Admins don't need a pass**, and previews are never capped | Admins check films before and after publishing |
| 16 | `VELORAUG_PASSES_REQUIRED`, **off by default** | Turning on payments is the owner's choice, made when prices are set and Pesapal works |
| 17 | The API's database role reads and writes **only the signed-in viewer's own** payments and passes, under row-level security. Pesapal's notifications, which have no viewer, find their payment's owner by the payment's tracking ID only | As for profiles since Milestone 5 |
| 18 | The database itself refuses a pass that doesn't match a completed payment of the same viewer, of the right length | A bug in the API can't hand out free passes |
| 19 | Pesapal's keys are in the API's `.env` only: `VELORAUG_PESAPAL_CONSUMER_KEY`, `VELORAUG_PESAPAL_CONSUMER_SECRET`, `VELORAUG_PESAPAL_IPN_ID`, `VELORAUG_PESAPAL_ENVIRONMENT` (`sandbox` or `live`), and `VELORAUG_PUBLIC_API_URL` for the return address | Like the TMDB token. Never in the app |
| 20 | **Pesapal's page address is checked** to be `https` on `pesapal.com` before the API passes it on, and again in the app before opening it | A bad answer can't send a viewer to another site to pay |

### Routes ruled out

| Route | Why not |
| --- | --- |
| Believing the return or the notification | Anyone can call them. Pesapal's own pages say to ask for the status |
| An embedded card or mobile money form | The app would handle payment details, and need PCI work |
| Pesapal's page inside the app (an iframe or web view) | On the web, the payment page and its mobile money prompts work best on their own. A new tab is simpler, and Android opens the browser anyway |
| A background job polling all payments | Three checks driven by real events cover it, without another process to run |
| Subscriptions (Pesapal's recurring payments) | Automatic renewal is out of Milestone 10 |

## 1. Database

Migration `0006_passes`.

| Table | What it holds |
| --- | --- |
| `pass_plans` | `day`, `week` and `month`, each with its days, and its price in UGX or null |
| `payments` | One per checkout: its ID (sent to Pesapal as the merchant reference), the viewer, the pass and its days and price **at the time**, the state, Pesapal's tracking ID, method and confirmation code, the email or phone sent, a reason when it failed, and when it was made, changed and completed |
| `passes` | One per completed payment: the viewer, when it starts and ends, and when it was revoked |

**Roles:**
- `veloraug_app`, the API's role:
  - reads `pass_plans`;
  - adds and changes **its own viewer's** payments, and adds **their** passes, under row-level security, as for profiles;
  - can find a payment's owner only by its tracking ID, set for that one transaction;
  - can see whether **its own viewer** is an admin, and nothing else in `admins`.
- `veloraug_editor`, the admin routes' role, reads `pass_plans` and changes only their prices.
- A trigger refuses a pass unless its payment is `completed`, belongs to the same viewer, and the pass is exactly the payment's days long.

## 2. The API

| Route | Who | What |
| --- | --- | --- |
| `GET /api/v1/passes/plans` | Anyone | The passes for sale, with their prices |
| `GET /api/v1/me/pass` | Signed in | Whether a pass is running, until when, and any payment still being checked. Checks the viewer's own unfinished payments of the last 24 hours first, up to 3 |
| `POST /api/v1/passes/checkout` | Signed in | Starts a payment for one pass: the payment row, then Pesapal's order. Answers Pesapal's page address. 409 if the pass isn't for sale, 503 if payments aren't set up, 502 if Pesapal refuses |
| `GET /api/v1/passes/payments/{id}` | The payment's viewer | Checks with Pesapal if it isn't settled, then answers its state and, once completed, when the pass ends |
| `GET /api/v1/passes/return` | Pesapal, in the viewer's browser | Checks the payment, and shows a short page saying to go back to VeloraUG |
| `GET /api/v1/passes/ipn` | Pesapal | Checks the payment, and answers in Pesapal's JSON |
| `POST /api/v1/items/{id}/playback` | Signed in | As before. With passes required: admins as before; others need a pass (402 without), and the grant ends no later than the pass |
| `GET`, `PATCH /api/v1/admin/pass-plans` | Admins | The passes, and their prices |

`python -m app.pesapal register-ipn <address>` registers the notification address with Pesapal, and prints the ID for `.env`.

## 3. The app

- **Account → Your pass:** whether a pass is running and until when; otherwise **Buy a pass**, with each pass and its price.
- **Buying:** the app starts the payment, opens Pesapal's page, and shows **Finish paying in the Pesapal tab**, checking every 3 seconds for up to 15 minutes, with **Check again** and **Cancel**. When it's completed, **Your pass is ready, until …**.
- **The player:** 402 shows **You need a pass to watch**, or **Your pass has ended** when playing had started, with **Buy a pass**. Once a pass is bought there, the player asks for a new grant and carries on from the same moment.
- **Admin → Settings → Pass prices:** a price for each pass, or none to stop selling it.

## Owner setup

### At 10E

1. Create a Pesapal **sandbox** account at Pesapal's developer site, or use the demo keys it publishes, and paste the consumer key and secret into `services/api/.env`. **Never in a message.**
2. Run `register-ipn` with the address Pesapal will call. Locally there's none Pesapal can reach: register `http://127.0.0.1:8000/api/v1/passes/ipn` all the same. Checking from the app covers it. Paste the printed ID into `.env`.
3. Set the prices in **Admin → Settings → Pass prices**, and `VELORAUG_PASSES_REQUIRED=true`. Restart the API.

## Acceptance criteria

### 10B API

- Migration `0006` runs and downgrades on a local Postgres. The app role can't see another viewer's payments or passes, or anything in `admins` but its own row. A pass for a payment that isn't completed, another viewer's, or the wrong length is refused by the database.
- Tests, with Pesapal faked, for:
  - prices, and a pass not for sale;
  - checkout, its order to Pesapal, and Pesapal's page address checked;
  - each status: completed, failed then completed, reversed, invalid, and abandoned after 24 hours;
  - a wrong amount, currency or reference refused;
  - the same completion seen twice making one pass;
  - a pass bought early starting when the last one ends;
  - the return page and the notification, with an unknown tracking ID;
  - grants: 402 without a pass, capped at the pass's end, unchanged for admins and with passes off.

### 10C app

- Widget tests for:
  - the Account tab with and without a pass;
  - buying, through to "Your pass is ready";
  - a failed payment;
  - the player's 402 before and during playback, and carrying on after buying;
  - pass prices in admin Settings.
- Every visible string comes from `app_en.arb`. The web build.

### 10E end to end

- With Pesapal's sandbox and passes required:
  - a viewer without a pass is refused;
  - they buy a day pass from the player, and the film carries on;
  - the payment shows in Pesapal's sandbox dashboard;
  - the pass's end is moved to the past by the owner (an SQL line in the run sheet), and the next grant is refused with "Your pass has ended";
  - a second pass bought early starts when the first ends.

## Risks

| Risk | What happens |
| --- | --- |
| **No rights, no payments.** Pesapal can close an account over content complaints, and charging needs the [launch checks](roadmap.md#check-before-launch): rights to each film and VJ edition, and TMDB's commercial terms | Live payments wait for those checks. The sandbox takes no money |
| A notification never arrives | The app checks while the viewer pays, and the Account tab checks again later. A payment completed after the app was closed shows up when it's next opened |
| Pesapal's sandbox behaves unlike live | 10E uses the sandbox. The live switch is one setting, and the first live payment is checked by hand |
| Pesapal reports a status we don't expect, such as `INVALID` while a payment is still open | It's treated as not yet paid until 24 hours pass. 10E notes what the sandbox really answers |
| A pass shared by sharing an account | Not prevented in Milestone 10. Device limits can follow |

## Sources

Pesapal API 3.0, read on 19 November 2026:
- [API reference](https://developer.pesapal.com/how-to-integrate/e-commerce/api-30-json/api-reference): sandbox `https://cybqa.pesapal.com/pesapalv3`, live `https://pay.pesapal.com/v3`
- [Authentication](https://developer.pesapal.com/how-to-integrate/e-commerce/api-30-json/authentication): `POST /api/Auth/RequestToken`, a token valid for at most 5 minutes
- [RegisterIPNURL](https://developer.pesapal.com/how-to-integrate/e-commerce/api-30-json/registeripnurl): `POST /api/URLSetup/RegisterIPN`, `url` and `ipn_notification_type`, answering `ipn_id`
- [SubmitOrderRequest](https://developer.pesapal.com/how-to-integrate/e-commerce/api-30-json/submitorderrequest): `POST /api/Transactions/SubmitOrderRequest`, with `id`, `currency`, `amount`, `description`, `callback_url`, `notification_id` and `billing_address`, answering `order_tracking_id` and `redirect_url`
- [GetTransactionStatus](https://developer.pesapal.com/how-to-integrate/e-commerce/api-30-json/gettransactionstatus): `GET /api/Transactions/GetTransactionStatus?orderTrackingId=`, `status_code` 0 invalid, 1 completed, 2 failed, 3 reversed, and the IPN reply `{"orderNotificationType", "orderTrackingId", "orderMerchantReference", "status": 200}`
