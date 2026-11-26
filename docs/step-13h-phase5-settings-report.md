# Step 13H, Phase 5: Settings

Written and built on 26 November 2026, as the last phase of the admin panel upgrade. Built on Phase 4 (pull request #24), which is built on #23, #22 and #21; none is merged yet. **Not yet deployed or checked against Neon. No screenshots were taken.**

## What Settings could do before

Only two things: **Admins** (add one by verified email, or remove one, never the last) and **Languages** (add one). Everything else, from Pesapal to the payment timeout, lived in the server's environment, and plans were under Subscriptions.

## What Settings has now

The page opens with **chips to jump to each part**. A part with unsaved changes is marked **Not saved**, and has **Undo changes**. A part not at its defaults has **Use defaults**.

| Part | What can be changed | Where it takes effect |
| --- | --- | --- |
| **Support contacts** | Email, phone and WhatsApp | The app's Settings gets a **Help and support** group: Chat on WhatsApp, Call us and Email us, with each one shown only if set |
| **Maintenance** | On or off, and a message, with a **preview** of what viewers will see | The app shows a notice above every screen, and **no passes can be bought** until it's off. Watching and downloads carry on |
| **Payments** | The **payment timeout** from Phase 4 (5 to 1,440 minutes; empty means the server's setting). Pesapal's mode is shown, read only | Stale payments are settled after this long |
| **Viewers** | How many days before a pass ends viewers are reminded (1 to 14, default 3) | The app's notifications |
| **Content defaults** | The language of new drafts. The upload limits (50 GB a video, 2 MB an image) and the qualities made are shown, read only | **New draft** starts with it, and uploads use it when no language is chosen |
| **Plans and pricing** | — | A button opens Subscriptions, where plans already live beside their payments |
| **Admins** | Add and remove, as before | Notes honestly that every admin can do everything |
| **Languages** | Add, as before | — |
| **About** | — | Server environment, API version, **database migration** (such as `0019`), and whether TMDB and playback are set up |

### Saving

- **The first five parts save together.** A bar at the bottom shows how many parts aren't saved, with **Save** and **Discard**. Only the settings that changed are sent.
- **Values are checked twice.** Phone numbers must start with `+256`, emails need an `@`, and numbers must be within their range. The server checks everything again.
- **If anything is wrong, nothing is saved.** Each wrong field is named in red, and the save bar says so. It used to be a snack bar, but that covered the Save button, which the tests found.
- **Edits are kept while you visit other admin tabs.** While any are unsaved, the browser asks before the page is closed.

## Proposed, not built

These can't be built properly yet, so they aren't on the page:

| Wanted | Why not yet | What it would need |
| --- | --- | --- |
| App name and branding | The name and logo are built into the app and the sign-in pages | A release of each, reading the setting |
| Auto-publish rules (e.g. publish when details, poster and VJ are ready) | Publishing is a deliberate check today: a wrong VJ credit harms a VJ | A rule in the media worker after a video is ready, with its own audit trail |
| Notification channels (email, SMS, push) | Nothing sends email or SMS, and push is "coming soon" in the app | A sending service and its keys |
| Admin roles (e.g. uploads only, or billing only) | Every route checks "is an admin", nothing finer | A role column on admins, and a check on each route |
| Upload limits and the quality ladder, editable | They are set in tusd's and the media worker's configuration | Those services reading Settings |
| Pesapal's keys and mode | Secrets must stay in the server's environment | — (shown read only) |
| The app's version in About | The app doesn't read its own build number yet | `package_info_plus`, or a build-time constant |
| Featuring a title on the home banner; scheduled publishing | Proposed in Phase 2 | Phase 2's report |

## Decisions to review

| Question | Decision | Why |
| --- | --- | --- |
| Where settings are stored | One table, `app_settings`, one JSON value per key; a key with no row has its default | Few settings, each checked in one place (`app/app_settings.py`). The database allows only known keys |
| The viewers' API reads every setting | Yes | Nothing secret is a setting, and the app needs support contacts, maintenance and reminders |
| What maintenance stops | Buying passes. Not watching or downloads | Taking money while something's broken is the real risk; stopping playback would punish paying viewers |
| The timeout: setting or environment | The setting wins; empty means the environment's | Admins can change it without a deploy, and a server without it still works |
| Admins may read the migration version | Yes, for About | It names the schema, nothing else |

## What changed

| File | Change |
| --- | --- |
| `migrations/versions/0019_app_settings.py` | `app_settings`. Admins read and write it; the viewers' API reads it. Admins may read `alembic_version` |
| `app/app_settings.py` | New: each setting, its default and its checks; reading with defaults; saving all or nothing |
| `app/settings_routes.py` | New: `GET`/`PATCH /api/v1/admin/settings`, and `GET /api/v1/status` for everyone |
| `app/pass_routes.py` | Checkout answers 503 with the maintenance message while maintenance is on |
| `app/account.py`, `app/account_routes.py` | Pass reminders use the admins' days |
| `app/admin_billing.py` | The payment timeout from Settings, or the server's |
| `app/admin.py` | New drafts use the default language when none is chosen |
| `lib/admin/settings_view.dart` | Settings, rebuilt |
| `lib/widgets/maintenance_banner.dart` | New: the notice, shared by the app and the admins' preview |
| `lib/shell/app_shell.dart` | Shows the notice while maintenance is on |
| `lib/screens/account/settings_screen.dart` | The app's Help and support |
| `lib/admin/new_draft_screen.dart` | Starts with the default language |
| `lib/admin/uploads/upload_platform*.dart` | The browser's "leave page?" warning now counts each reason, so uploads and Settings don't turn off each other's |
| `lib/api/admin_api.dart`, `lib/api/catalogue_api.dart` | The new calls; refused settings name each field |
| `lib/l10n/app_en.arb` | 61 new strings |

## Deploying

1. Run migration **0019**, after 0015 to 0018, before the API.
2. **The app keeps working without it.** If the settings can't be read, every setting has its default.

## How to test it

1. Open **Settings**. Add a WhatsApp number and press **Save**. In the app, **Account → Settings** has Help and support, with Chat on WhatsApp.
2. Turn on **Maintenance mode** with a message. The preview shows it. Save. The app shows the notice, and buying a pass says the message.
3. Type a phone number without +256 and press Save. It's named in red, and nothing is saved.
4. Change something, then visit Drafts and come back: the change is still there. Close the tab: the browser asks first.

## Checks done

- **API:** 870 tests pass, 1 skipped, with 26 new in `tests/test_settings.py`. `ruff check` and `ruff format --check` are clean.
  - Good values tidied (9 cases) and bad ones refused (10).
  - Defaults and the server's setup shown.
  - Settings saved, reset to their defaults, and never half saved.
  - The app reads maintenance and support contacts.
  - No pass sold during maintenance.
  - The payment timeout set here wins over the server's.
  - Viewers reminded as many days ahead as set.
  - New drafts take the default language.
- **App:** 740 tests pass, with 11 new in `test/admin_settings_test.dart`. `flutter analyze` is clean.
  - Every part, and what the server is set up with.
  - Only changed settings saved, from the bar.
  - A part's undo, and Discard.
  - Wrong values named, here and by the server.
  - The payment timeout back to the server's.
  - Maintenance's preview and save.
  - Changes kept across tabs.
  - A narrow phone with large text.
  - In the app: the maintenance notice; none without it, or from an older server; and Help and support with only the contacts that are set.
- **Fixed on the way:** each admin's Remove button sat beside their email, which didn't fit a narrow phone with large text. It now sits underneath.
