# Step 10E run sheet: a sandbox pass from start to end

For the owner, on this PC, with Neon's development branch and **Pesapal's sandbox**. No real money moves. It checks the [10E criteria](step-10a-payments-plan.md#10e-end-to-end). Write down what you see at each step, and send it back, including anything that fails.

**Before you start:** the 9F run sheet's setup works (the API, the media worker and the app run, and at least one film is published and plays).

> **Updated 21 November 2026 for Milestone 10's six tiers and devices.** Run [Migration 0007](#migration-0007) instead of step 1, use the tiers in steps 3 to 7, and add steps 10 to 15. Nothing here uses live Pesapal keys or real money.

## Migration 0007

Run this on Neon's **development** branch first. On production, only once the whole run sheet has passed on development, and only with the owner's go-ahead.

**Order matters:** migrate **before** the API from this branch runs against that database. The new API reads `0007`'s columns; on a `0006` database its pass and account routes would fail. Today's API keeps working on `0007`. Don't run `infra/production-database.sh` again for this: it upgrades to `head` without the checks below.

1. **Backup.** In the Neon Console, open the project, **Branches → Create branch**, from the branch you'll migrate, at the current time. Name it `backup-before-0007-<date>`. Check it's listed, with its parent and time. Neon keeps it until you delete it; restoring is **Branches → … → Restore**.
2. **Preflight**, read-only, with the owner string pasted when asked:

   ```powershell
   cd services\api
   .\.venv\Scripts\python.exe scripts\preflight_0007.py
   ```

   **Expect:** every line `PASS`, and the counts of payments, passes and completed payments. Write the counts down. If anything says `FAIL`, stop and send it back.
3. **Review the SQL** without running it, if you wish: `.\.venv\Scripts\python.exe -m alembic upgrade 0006:0007 --sql`.
4. **Migrate**, explicitly to `0007`:

   ```powershell
   .\.venv\Scripts\python.exe -m alembic upgrade 0007
   .\.venv\Scripts\python.exe -m alembic current
   .\.venv\Scripts\python.exe scripts\check_database.py
   ```

   **Expect:** `0007 (head)`, and every check `PASS`, including "the six tiers, with their days and devices" and "a fourth device is refused".
5. **Compare** in the SQL editor: `select count(*) from public.payments; select count(*) from public.passes;` match step 2, and `select id, display_name, price_ugx, days, max_devices, for_sale from public.pass_plans order by display_order;` shows the six tiers on sale and `day`, `week`, `month` off sale.

If step 4 fails part-way, the migration runs in one transaction and nothing changes; send back the error. Never downgrade a hosted branch.

## 1. Run the migration (before Milestone 10)

Migration `0006_passes` adds pass prices, payments and passes. As for earlier migrations, paste the owner connection string into your own terminal only, **never in a message**:

```powershell
cd services\api
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m alembic current
.\.venv\Scripts\python.exe scripts\check_database.py
```

The first two each ask for the owner string, as in the [API README](../services/api/README.md#3-run-the-migration).

**Expect:** `current` shows `0006 (head)`, and every check says `PASS`, including the four new pass checks.

## 2. Pesapal's sandbox keys

1. Get sandbox keys from Pesapal's developer site (developer.pesapal.com), either your own sandbox account's or the demo keys it publishes for Uganda.
2. Add them to `services\api\.env`, **never in a message**:

   ```text
   VELORAUG_PESAPAL_CONSUMER_KEY=<the key>
   VELORAUG_PESAPAL_CONSUMER_SECRET=<the secret>
   VELORAUG_PESAPAL_ENVIRONMENT=sandbox
   ```

3. Restart the API container, then register the notification address:

   ```powershell
   docker compose -f infra\compose.local.yaml --profile uploads up -d api
   docker compose -f infra\compose.local.yaml exec api python -m app.pesapal register-ipn https://api.veloraug.com/api/v1/passes/ipn
   ```

4. Copy the printed `VELORAUG_PESAPAL_IPN_ID=...` line into `.env`, add the two lines below, and restart the API again:

   ```text
   VELORAUG_PUBLIC_API_URL=http://127.0.0.1:8000
   VELORAUG_PASSES_REQUIRED=true
   ```

**Expect:** `Registered with Pesapal's sandbox.` Pesapal refuses a local address (found on 22 November 2026: `invalid_url ... not a local address`), so a public one is registered only to get an ID. Notifications go to the production API, which has no Pesapal keys and answers 503 without changing anything; on this PC, the app checks the payment itself.

## 3. The plans

The six tiers come with their approved prices. In the app, signed in as an admin: **Admin → Subscriptions**. Check the six plans, with Velora Prime featured. Change Velora Flex's price to **10,500**, **Save**, then back to **10,000**, **Save**.

**Expect:** "Velora Flex saved." each time, and two lines under **Price history**. `day`, `week` and `month` say "Legacy pass, kept for history", with no price field.

## 4. A viewer without a pass is refused

Sign in **as an account that isn't an admin** (admins never need a pass). Open a published film and press **Watch**.

**Expect:** "You need a pass to watch", with **Buy a pass**. Account → Your pass says "You don't have a pass."

## 5. Buy a plan from the player

1. Press **Choose a plan**, then **Pay UGX 6,000** on Velora Start.
2. Pesapal's sandbox page opens in a new tab. Pay with one of the sandbox test methods Pesapal lists.
3. Go back to the VeloraUG tab.

**Expect:** "Finish paying on Pesapal" while you pay, then **Your pass is ready**, with when it ends, within a few seconds of paying. **Carry on watching** plays the film. Pesapal's tab ends on VeloraUG's page saying you can close it.

**Also note:** what Pesapal's sandbox reported before you paid, if you can see it in the API's log (`payment ... not reported yet`), and how long it took to show as ready.

## 6. The payment in Pesapal's dashboard

Sign in to Pesapal's sandbox dashboard. **Expect:** the payment, for UGX 6,000, described as "VeloraUG Velora Start, 7 days". Account → Payments shows it as **Paid**, with Pesapal's reference.

## 7. A pass bought early starts when the first ends

Account → My membership → **Change plan** → **Velora Duo**, and pay.

**Expect:** My membership still shows **Velora Start**, 1 registered device, and "Next: Velora Duo, from" the day Velora Start ends, 7 days from now.

## 8. The pass ends

End the test viewer's passes now, from the Neon console's SQL editor on the development branch. Replace the email with the test viewer's. It changes only their passes, and is the only change to data by hand in this run sheet:

```sql
update public.passes
set starts_at = now() - interval '8 days', ends_at = now() - interval '1 minute'
where user_id = (
  select id from neon_auth."user" where lower(email) = lower('viewer@example.com')
);
```

**Expect:** `UPDATE 2`, one for each pass bought. (Through the API's own roles the database refuses to move a pass that has started; the owner, by hand, may.)

Then press **Watch** again.

**Expect:** "You need a pass to watch". If a film was already playing, within a minute or two of the next grant renewal: "Your pass has ended", with **Buy a pass**.

## 9. Switch passes off again

Set `VELORAUG_PASSES_REQUIRED=false` in `.env` and restart the API, so viewing carries on as before until launch.

## 10. Devices: registered once, and limited

Before step 8's SQL, or with a fresh viewer who has Velora Start: watch a film in Chrome. Then Account → **My devices**.

**Expect:** one device, "Web browser", marked **This device**. In a second tab of the same browser, it's the same device. In Edge, or on the phone, pressing **Watch** says **Device limit reached** with **Manage devices**.

## 11. Two devices on Velora Duo

For a fresh test viewer, buy **Velora Duo**. Register Chrome and the phone by pressing **Watch** on each, and play on both at once. Then try a third browser.

**Expect:** both play together, and the third says **Device limit reached**. Account → My devices shows two devices, "Your plan allows 2 registered devices."

## 12. Removing a device stops it

While the phone plays, in Chrome: Account → My devices → the phone → **Remove**.

**Expect:** within about a minute the phone's film stops and says **Playback stopped**. Pressing **Watch here again** registers it as a new device.

## 13. Stopping playback elsewhere

While Chrome plays, on the phone Account → My devices → **Playing now** → **Stop**.

**Expect:** Chrome's film stops within about a minute.

## 14. A reversal

In Pesapal's sandbox dashboard, if it lets you reverse or refund a sandbox payment, reverse the Velora Start payment. Otherwise note that it couldn't be tried.

**Expect:** after Pesapal's notification, or the next Account visit, Payments shows **Reversed**, Velora Start is gone from My membership, and Velora Duo starts now.

## 15. The media gateway's check

Only after the Worker from this branch is deployed with `API_URL` (Step 11D). With a film playing, run step 8's SQL.

**Expect:** the film stops within about a minute, not when its grant ends.

## What to send back

For each step: **pass** or **fail**, and what you saw. For step 5, how long the pass took to show as ready, and the payment method you used.
