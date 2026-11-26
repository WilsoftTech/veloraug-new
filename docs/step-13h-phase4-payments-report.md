# Step 13H, Phase 4: Subscriptions and Payments

Written and built on 26 November 2026, as Phase 4 of the admin panel upgrade. Built on Phase 3 (pull request #23), which is built on #22 and #21; none is merged yet. **Not yet deployed, and not checked against Neon or Pesapal's live service:** Pesapal was the test suite's fake. No screenshots were taken.

## The bug: unpaid payments stayed "pending" for ever

**Why it happened:** a payment only moved on when something asked Pesapal about it: the viewer's app while they waited, or Pesapal's notification. If the viewer closed the app and no notification came, nothing ever asked again, so the payment stayed "pending". The 24-hour give-up rule existed, but it only ran inside one of those checks.

**The fix:**
- **Every time an admin opens Subscriptions**, the server finds payments still open after the **timeout** and settles them, 20 at a time.
- **Each one sent to Pesapal is asked about first:**
  - Paid after all: it's completed and the pass is made.
  - Failed: marked failed.
  - Otherwise: **given up on, shown as "Expired"** with the reason "Not paid within 1 hour".
- **A payment that never reached Pesapal** expires straight away.
- **If Pesapal isn't answering**, nothing is guessed: those payments wait for the next look.
- **A payment paid after it expired is still honoured.** Pesapal's notification, or an admin's **Re-check with Pesapal**, completes it and makes its pass. Before, a late payment's money arrived but no pass was ever made.
- **"Waiting for payment"** now counts every payment still open, not just the last 24 hours, because stale ones are settled before it's counted.

**The timeout** is a setting: `VELORAUG_PAYMENT_TIMEOUT_MINUTES`, from 5 to 1,440, **default 60**. Phase 5's Settings page is the natural place to show it.

### Why on-read and not a scheduled job

The prompt asked me to choose. I chose **on-read**:
- **There's no scheduler to run a job.** The API and the media worker are the only processes, and adding a cron job is a deployment change.
- **The pending list is right whenever someone looks.** Payments are only shown in Subscriptions and in the viewer's own history, and the viewer's app already checks its own open payments.
- **The trade-off:** if no admin opens Subscriptions for a while, stale rows stay "pending" in the database until someone does. Nothing depends on them meanwhile. A cron job calling the same function can be added later without changing it.

## What an admin sees now

### Overview

- **Figures:**
  - money taken today, in 7 days and in 30 days
  - **success rate**: paid, of payments settled in 30 days
  - active subscribers, and **passes ending within 3 days** with nothing after them
  - waiting for payment, failed, refunded, **free days given**, devices, and playing now
  - subscribers by plan.
- **A chart of money taken each day for 30 days** (Kampala days):
  - One series in the app's accent colour. The `dataviz` checks were run: the colour passes on the dark surface; the lighter blue failed the lightness band, so it wasn't used.
  - Each day's whole column is a hover or tap target, with "Nov 26: UGX 12,000, 2 payments".
  - **Show as table** lists the same days.

### Payments

- **Search** by email, phone (a local "0772…" number finds "+256772…"), account or payment ID, Pesapal tracking ID, or confirmation code.
- **Filter** by state (Waiting, Paid, Failed, Expired, Reversed, Refunded), plan and date range. 50 at a time, with **Show more**.
- **Export CSV** with the same filters, up to 10,000 rows:
  - Contacts are masked, as on screen.
  - Any cell that a spreadsheet would read as a formula, like `=…`, is made safe.
  - It downloads in the browser.
- **Tap a payment** to open its detail:
  - contact, method, confirmation code, Pesapal tracking ID, payment ID and reason
  - **what happened, step by step:** started, sent to Pesapal, paid / failed / expired / reversed, refunded. Sending to Pesapal has no recorded time, and says so.
  - the pass it made
  - actions: **Re-check with Pesapal**, **Mark refunded** (for paid ones, confirmed first), and **Open account**.

### Subscribers and their accounts

- **Search** by email, phone or account ID, or show **only those ending within 3 days**.
- **A subscriber's account:**
  - passes: running, still to come, over or ended early, and whether each was **bought** or **free days**
  - payments, which open the same detail
  - free days given, with who gave them and why
  - devices, which can be removed.
- **Give free days:**
  1. Choose a plan, from 1 to 90 days, and **give a reason**, which is required.
  2. The days start when the account's passes end, or now if it has none. So it **extends** a pass, or **starts** one.

### Plans and price history

Plans, prices, on-sale and featured switches, and price history are **kept as they were**, below the rest.

## Decisions to review

| Question | Decision | Why |
| --- | --- | --- |
| Timeout | 60 minutes, a setting | Pesapal's mobile-money prompts time out in minutes; an hour allows for card checkouts. A late payment is still honoured, so a short timeout costs no one a pass |
| Free days | A **grant**, its own record, never a payment | Fake payments would inflate revenue and success rates, and break refunds. A pass is now either bought or granted, and the database checks it |
| Refunds through Pesapal's API | **Not built** | Pesapal has a refund request API, but I couldn't check it against their sandbox, and untested code that moves money is a risk. Refunds stay on Pesapal's dashboard, then **Mark refunded** here, as before. The payment detail says how |
| The timeline | Built from the times already recorded | Recording every step would add a table written on each Pesapal answer. The times shown are real; "sent to Pesapal" says its time wasn't recorded |
| "Expired" | The admins' word for `abandoned` | The database keeps its state name, so nothing else changes |
| Success rate | Paid, including later refunded, ÷ all payments settled in 30 days | Still-open payments don't count against it |

## What changed

| File | Change |
| --- | --- |
| `migrations/versions/0018_pass_grants.py` | `pass_grants`. A pass's payment becomes optional, with `grant_id` and a check that a pass has exactly one of the two. The pass check accepts a granted pass. `grant_pass` gives days after the account's passes, under the same lock as a bought pass |
| `app/passes.py` | Stale payments settled: Pesapal asked first, nothing guessed while it's down. A late payment is honoured. The timeout is passed in. Granted passes are read with their plan's name |
| `app/admin_billing.py` | Settling on each look; the new figures and daily totals; `GET /transactions` and `/transactions.csv`; `GET /payments/{id}` with its steps and pass; `POST /payments/{id}/recheck`; `POST /users/{id}/grants`; subscribers searched and ending soon; grants on an account. All audit-logged |
| `app/config.py` | `payment_timeout_minutes` |
| `app/account.py` | A granted pass's notifications name its plan |
| `lib/admin/subscriptions_view.dart` | The tab, rebuilt |
| `lib/admin/payment_sheet.dart` | New: a payment's detail and actions |
| `lib/admin/account_billing_screen.dart` | New: an account, and giving free days |
| `lib/admin/revenue_chart.dart` | New: the 30-day chart and its table |
| `lib/admin/save_file*.dart` | New: saving the CSV in the browser |
| `lib/api/admin_api.dart` | The new calls |
| `lib/l10n/app_en.arb` | 71 new strings |
| `test/admin_billing_test.dart` | The Subscriptions tests, moved out of `pass_screens_test.dart` and updated, with new ones |

**About `pass_screens_test.dart`:** it had your uncommitted changes. I moved its two admin Subscriptions tests to the new file and **committed only that removal**. Your own changes to it are still uncommitted, exactly as they were.

## Deploying

1. Run migration **0018** (after 0015 to 0017) before the API.
2. Optionally set `VELORAUG_PAYMENT_TIMEOUT_MINUTES`. Without it, the timeout is 60.
3. On the first visit to Subscriptions after deploying, old stuck payments are settled, 20 per visit. If there are many, refresh a few times.

## How to test it

1. Start buying a pass in the app and close it without paying. After the timeout, open Subscriptions: it's shown as **Expired**, "Not paid within 1 hour".
2. Pay for one, then mark it expired by hand in the database. Open it and press **Re-check with Pesapal**: it's Paid, and the viewer has a pass.
3. Search for a phone number as "0772…". Filter by Paid and a date range. Press **Export CSV**: a spreadsheet downloads.
4. Open a subscriber and give 3 free days with a reason. Their pass ends 3 days later. Revenue doesn't change.

## Checks done

- **API:** 844 tests pass, 1 skipped, with 15 new. `ruff check` and `ruff format --check` are clean.
  - `tests/test_admin_payments.py` (15):
    - the bug reproduced and fixed: an unpaid payment stops showing pending once expired, after asking Pesapal
    - a recent one stays pending
    - one paid after all is completed with its pass
    - one never sent to Pesapal expires
    - with Pesapal down, nothing is guessed
    - a payment paid after it expired is honoured by Pesapal's notification
    - the timeout is a setting
    - the overview's money, success rate, passes ending and daily totals
    - transactions filtered, searched (a local phone number too) and paged, with contacts masked
    - the CSV export, masked and formula-safe, admins only
    - a payment's steps and pass
    - re-checking with Pesapal, with Pesapal down, and for a payment never sent
    - free days starting a pass or extending one, never counted as money
    - free days checked
    - subscribers searched, and those ending soon.
- **App:** 729 tests pass. That's 6 more than before: the 2 Subscriptions tests moved out of `pass_screens_test.dart`, updated, plus 6 new. `flutter analyze` is clean.
  - `test/admin_billing_test.dart` (8):
    - the overview and chart, with its table
    - plans and prices saved
    - payments filtered, searched and exported
    - a payment's steps, and marking it refunded only once confirmed
    - an expired payment re-checked
    - subscribers searched and ending soon
    - an account's passes and free days, and giving more, with a reason required
    - a narrow phone with large text.
- **Layout fixed on a 320-pixel phone with large text:** the chart's header, its date labels, the plans' switches, and the payment detail's steps overflowed. Each now wraps or moves its time underneath.
