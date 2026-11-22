# Step 10H run sheet: one controlled live payment

For the owner. It takes Milestone 10 to production with **Pesapal's live keys**, while **`VELORAUG_PASSES_REQUIRED` stays `false`**: invited viewers keep watching free, and nobody is asked to pay. Then the owner, and only the owner, buys one plan with real money, checks it end to end, and refunds it.

Charging viewers, by turning `VELORAUG_PASSES_REQUIRED` on, is a separate decision, after the [launch checks](roadmap.md#check-before-launch).

Keys, connection strings and IPN IDs go into files on the server only, **never in a message**.

## 0. Already done (22 November 2026)

- [x] Migration `0007` on the development branch: preflight 11/11, `check_database.py` 38/38
- [x] A sandbox payment with Pesapal's test card: completed, confirmed by the API, Velora Flex active for exactly 14 days
- [ ] Velora Flex set back to UGX 10,000 on development (Admin → Subscriptions)
- [ ] **Watch** on the PC: the device registers itself and plays; Account → My devices shows it as **This device**

## 1. Merge

The branch `feature/milestone-10-subscriptions` is merged into `main` through a pull request, after review. It also brings the seven Step 11 commits that are on `feature/step-09-vj-catalogue` but not yet on `main`.

## 2. Production's database

1. **Backup.** Neon Console → the production project → **Branches → Create branch** from the default branch, now. Name it `backup-before-0007-<date>`, and check it's listed.
2. **Migrate**, over SSH on the server:

   ```bash
   cd /opt/veloraug/repo && git fetch origin main && git checkout main && git merge --ff-only origin/main
   bash /opt/veloraug/repo/infra/production-migrate-0007.sh
   ```

   It runs the preflight first. **Expect:** every line `PASS`. Write down the counts. Type `MIGRATE` only if everything passed and the backup is listed. **Expect:** `0007 (head)`, then every database check `PASS`.

Never downgrade production. If anything fails, stop and send back what it printed.

## 3. Deploy the API, with passes still off

In `/opt/veloraug/env/api.env`, check that `VELORAUG_PASSES_REQUIRED` is absent or `false`. Then:

```bash
bash /opt/veloraug/repo/infra/deploy.sh --migrated
curl -s https://api.veloraug.com/api/v1/passes/plans
```

**Expect:** the health checks pass, and the six plans are listed. An invited viewer can still watch a film, with no plan and no device registration.

## 4. Pesapal live keys and the notification address

1. Add these lines to `/opt/veloraug/env/api.env`, keeping the file mode at `600`:

   ```text
   VELORAUG_PESAPAL_CONSUMER_KEY=<live key>
   VELORAUG_PESAPAL_CONSUMER_SECRET=<live secret>
   VELORAUG_PESAPAL_ENVIRONMENT=live
   VELORAUG_PUBLIC_API_URL=https://api.veloraug.com
   ```

2. Restart, and register the address with the **live** account:

   ```bash
   bash /opt/veloraug/repo/infra/deploy.sh --no-pull
   docker compose -f /opt/veloraug/repo/infra/compose.prod.yaml exec api \
     python -m app.pesapal register-ipn https://api.veloraug.com/api/v1/passes/ipn
   ```

   **Expect:** `Registered with Pesapal's live.` Add the printed `VELORAUG_PESAPAL_IPN_ID=...` line to `api.env`, then `bash /opt/veloraug/repo/infra/deploy.sh --no-pull` again.

3. **Expect:** `https://api.veloraug.com/api/v1/passes/ipn` in a browser now answers `422`, because no tracking ID was given, rather than `503` "Buying passes isn't set up on this server."

## 5. The media gateway and the web app

From the PC:

```powershell
cd C:\Users\Wilsoft\veloraug\services\media_gateway
npx wrangler deploy --env production
```

**Expect:** the deploy lists `API_URL: "https://api.veloraug.com"`. Then build and deploy the web app as in [Deploy the web app and sign-in pages](../infra/README.md#deploy-the-web-app-and-sign-in-pages).

## 6. The controlled live payment

Signed in on `https://app.veloraug.com` with **your own** account:

1. Account → **Choose a plan** → **Pay UGX 6,000** on Velora Start. Pay with **your own** MTN, Airtel or card.
2. **Expect:** "Your pass is ready" within seconds of paying. Account → My membership shows **Velora Start**, 7 days; Payments shows **Paid** with Pesapal's reference.
3. In Pesapal's **live** dashboard: the payment for UGX 6,000, "VeloraUG Velora Start, 7 days".
4. **The notification:** within a few minutes, the API's log shows a `GET /api/v1/passes/ipn` answered `200`:

   ```bash
   docker compose -f /opt/veloraug/repo/infra/compose.prod.yaml logs api --since 30m | grep passes/ipn
   ```

5. Admin → Subscriptions: 1 active subscriber, UGX 6,000 revenue, and the payment with your masked email.

## 7. Refund it

In Pesapal's live dashboard, refund or reverse the payment, if your account allows it. **Expect:** after Pesapal's notification, or the next Account visit, Payments shows **Reversed** and My membership shows **No active plan**. If the dashboard doesn't allow it, note that, and keep the plan.

## 8. What to send back

For each step, **pass** or **fail** and what you saw, never a key. Then decide separately when to turn on `VELORAUG_PASSES_REQUIRED`.
