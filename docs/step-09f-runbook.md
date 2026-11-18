# Step 9F: run sheet

The owner's steps to put Milestone 9 on Neon and Cloudflare, and to publish the first real VJ editions. Each step says what to check before going on. Planned in the [VJ catalogue plan](step-09a-vj-catalogue-plan.md#9f-end-to-end).

Secrets never go in a message or a commit: paste them only when a script asks.

## Already checked

- `neondb_owner` can read `neon_auth."user"` on the development branch, and its `id`, `email`, `emailVerified` and `banned` columns are as `0005` expects. Adding an admin by email will work. (Checked 18 November 2026, read-only.)
- The development branch is at `0004`.

## 1. Stop what uses the old columns

`0005` renames `movie_id` to `item_id` on `upload_keys` and `media_originals`. Stop the API, the upload hooks and the media worker first, so nothing writes with the old names:

```powershell
docker compose -f infra/compose.local.yaml down
```

Stop any `uvicorn` or worker you started by hand too. Don't upload while the database is being upgraded.

## 2. Run migration 0005

From `services/api`:

```powershell
.\.venv\Scripts\python.exe -m alembic upgrade head --sql
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m alembic current
```

Check: `current` shows `0005 (head)`.

## 3. The editor role and the first admin

```powershell
.\.venv\Scripts\python.exe scripts\create_app_role.py --role editor
.\.venv\Scripts\python.exe scripts\catalogue.py admin add <your Neon Auth user id>
.\.venv\Scripts\python.exe scripts\check_database.py
.\.venv\Scripts\python.exe scripts\check_media_role.py
```

Your user ID is in the Neon Console, under **Auth**, **Users**. Check: both check scripts pass (`check_media_role.py` prints **15 PASS**), and `catalogue.py list` shows the four test films as test editions.

## 4. Redeploy the media gateway

From `services/media_gateway`:

```powershell
npm test
npm run deploy
```

Check that the image route is there:

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" -X PUT https://veloraug-media-dev.veloraug.workers.dev/i/x
```

The new Worker answers `404`; the old one answered `405`. The Matrix still plays: its links didn't change.

## 5. Start everything again on the new code

```powershell
docker compose -f infra/compose.local.yaml up --build -d
```

Then run the app in Chrome with `dart_defines.local.json`, as in the [app README](../apps/client/README.md#connect-to-the-local-api), and sign in. Check: **Admin** appears in the menu, and Home shows the four test films with no VJ label.

## 6. Publish a real translated movie

You need a translated film you're allowed to publish.

1. **Admin → New draft**, as a movie, with its title as the VJ's edition is known. Copy the key.
2. Upload: `python tools/veloraug_upload.py "<file>"`, and paste the key.
3. **Refresh** Drafts until the video is ready. The draft is looked up on TMDB by itself.
4. On the draft: **Preview** it; choose or confirm the details; choose a poster, or upload one; confirm the VJ credit, adding the VJ if needed; **Publish**.
5. In **VJs**, give the VJ a photo and a bio.

Check: Home shows it with the VJ's name on the poster, and in the VJ's row. Its page shows **Luganda · VJ …** and **Trailer**. It plays.

## 7. Publish a series of two episodes

1. **New draft** as a series, season 1, episode 1. Upload it as above.
2. On its page, **Add episode** for season 1, episode 2. Upload it with its own key.
3. Confirm the details, poster and VJ credit, and **Publish**. Episodes with a ready video are approved when publishing; a later one needs **Approve episode**.

Check, on the web and on the phone (Galaxy S20):

- The series lists both episodes. Episode 1 plays.
- At its end, **Up next: S1 E2** appears, and **Next episode** plays episode 2. The bar's **Next episode** does the same.

## 8. A second admin

Ask someone to sign in to VeloraUG once, with a confirmed email. In **Admin → Settings**, add them by email. Check: they see **Admin**. Remove them, and check they no longer do. The last admin can't be removed.

## 9. Delete the test films

Once a real edition is published:

```powershell
.\.venv\Scripts\python.exe scripts\catalogue.py delete-test-films
.\.venv\Scripts\python.exe scripts\catalogue.py uploads
.\.venv\Scripts\python.exe scripts\catalogue.py delete-test-films
```

The first run hides them and has the worker remove their videos from R2. Run it again once `uploads` shows them removed. Check: Home shows only real editions.

## What to send back

- `alembic current`, and the output of both check scripts.
- For each check above: passed, or what you saw instead.
- Whether Next Episode worked on the phone.
