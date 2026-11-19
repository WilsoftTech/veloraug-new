# Step 10E run sheet: a sandbox pass from start to end

For the owner, on this PC, with Neon's development branch and **Pesapal's sandbox**. No real money moves. It checks the [10E criteria](step-10a-payments-plan.md#10e-end-to-end). Write down what you see at each step, and send it back, including anything that fails.

**Before you start:** the 9F run sheet's setup works (the API, the media worker and the app run, and at least one film is published and plays).

## 1. Run the migration

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
   docker compose -f infra\compose.local.yaml exec api python -m app.pesapal register-ipn http://127.0.0.1:8000/api/v1/passes/ipn
   ```

4. Copy the printed `VELORAUG_PESAPAL_IPN_ID=...` line into `.env`, add the two lines below, and restart the API again:

   ```text
   VELORAUG_PUBLIC_API_URL=http://127.0.0.1:8000
   VELORAUG_PASSES_REQUIRED=true
   ```

**Expect:** `Registered with Pesapal's sandbox.` Pesapal can't reach `127.0.0.1`, so no notifications arrive: the app checks the payment itself.

## 3. Set the prices

In the app, signed in as an admin: **Admin → Settings → Pass prices**. Set the day pass to **1000**, the week to **5000**, and leave the month empty. **Save prices**.

**Expect:** "Prices saved."

## 4. A viewer without a pass is refused

Sign in **as an account that isn't an admin** (admins never need a pass). Open a published film and press **Watch**.

**Expect:** "You need a pass to watch", with **Buy a pass**. Account → Your pass says "You don't have a pass."

## 5. Buy a day pass from the player

1. Press **Buy a pass**, then **1 day, UGX 1,000**.
2. Pesapal's sandbox page opens in a new tab. Pay with one of the sandbox test methods Pesapal lists.
3. Go back to the VeloraUG tab.

**Expect:** "Finish paying on Pesapal" while you pay, then **Your pass is ready**, with when it ends, within a few seconds of paying. **Carry on watching** plays the film. Pesapal's tab ends on VeloraUG's page saying you can close it.

**Also note:** what Pesapal's sandbox reported before you paid, if you can see it in the API's log (`payment ... not reported yet`), and how long it took to show as ready.

## 6. The payment in Pesapal's dashboard

Sign in to Pesapal's sandbox dashboard. **Expect:** the payment, for UGX 1,000, described as "VeloraUG pass, 1 day".

## 7. A pass bought early starts when the first ends

Account → Your pass → **Buy another pass** → **1 week**, and pay.

**Expect:** "Your pass runs until" tomorrow, and "With the pass you bought next, you can watch until" 8 days from now.

## 8. The pass ends

End the test viewer's passes now, from the Neon console's SQL editor on the development branch. Replace the email with the test viewer's. It changes only their passes, and is the only change to data by hand in this run sheet:

```sql
update public.passes
set starts_at = now() - interval '8 days', ends_at = now() - interval '1 minute'
where user_id = (
  select id from neon_auth."user" where lower(email) = lower('viewer@example.com')
);
```

**Expect:** `UPDATE 2`, one for each pass bought.

Then press **Watch** again.

**Expect:** "You need a pass to watch". If a film was already playing, within a minute or two of the next grant renewal: "Your pass has ended", with **Buy a pass**.

## 9. Switch passes off again

Set `VELORAUG_PASSES_REQUIRED=false` in `.env` and restart the API, so viewing carries on as before until launch.

## What to send back

For each step: **pass** or **fail**, and what you saw. For step 5, how long the pass took to show as ready, and the payment method you used.
