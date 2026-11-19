# Step 10A plan: passes and payments

Date: 19 November 2026. This plans Milestone 10 in the [roadmap](roadmap.md): prepaid **daily, weekly and monthly passes**, paid through Pesapal. It follows [the look ahead in the Milestone 9 plan](step-09a-vj-catalogue-plan.md#7-looking-ahead-to-milestone-10-passes). **Steps 10B to 10D were written and built on 19 November 2026 at the owner's request to implement Milestone 10, with this plan not yet approved.** Step 10E needs the owner and Pesapal's sandbox.

Facts about Pesapal come from its [API 3.0 pages](#sources), as read on this date.

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
