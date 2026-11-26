# Step 13H, Phase 3: VJs

Written and built on 26 November 2026, as Phase 3 of the admin panel upgrade. Built on Phase 2 (pull request #22), which is built on Phase 1 (#21). Neither is merged yet. **Not yet deployed or checked against Neon. No screenshots were taken:** the screens were checked with widget tests, not in a browser against a running API.

## What an admin sees now

### The VJs list

- Each VJ shows:
  - photo, name and other spellings
  - **"12 published · 2 drafts · 340 viewers in 30 days"**
  - badges: **Active** or **Inactive**, **Featured**, and their **place** in the app's list.
- **Search** by name or by any other spelling: "junior" finds VJ Junior.
- **Filter:** all, active, inactive, featured.
- **Sort:** by name, most titles, most viewers, or **as in the app**.

### A VJ's page

Tapping a VJ opens their own page:

- **Profile:** photo, bio, other spellings, and their links (Facebook, Instagram, TikTok, YouTube, X, WhatsApp, website).
- **Their titles:** everything of theirs in the Library, published, hidden or withdrawn, with each one's viewers and state. Each opens in the editor. Their drafts are counted, with a pointer to Drafts.
- **Actions:**
  - **Change this VJ:** name, other spellings, bio, photo, and now their links, **Featured**, and their **place in the list**. Each link has to be a whole `https://` address, on that site.
  - **Make inactive:** they leave the app's VJ list, and their page can't be found. **Their titles stay, still credited to them**, and can still be watched. The confirmation says so. **Make active** undoes it.
  - **Merge into another VJ**, for duplicates such as "Vj Jnr" and "VJ Junior":
    1. Choose the VJ who stays. The confirmation says how many titles will move.
    2. Every title moves to them, and the duplicate's name and spellings are kept as their other spellings, so future uploads named either way are matched.
    3. If the VJ who stays has no photo or bio, they take the duplicate's.
    4. The duplicate is deleted, and you're taken to the page of the VJ who stayed.
  - **Delete permanently**, offered only for a VJ with no titles.

### In the app

- **Featured VJs come first** in the app's VJ list. Then VJs with a place, smallest first. Then the rest, by name.
- **A VJ's page shows their links** as buttons that open the site, such as "VJ Emmy on Facebook". Only `https` links are shown.
- **Inactive VJs** are left out of the list, and their page isn't found. Their titles still name them.

## Names are kept unique

- **Two VJs can't have the same name**, whatever the capitals. This was already the case.
- **New: a VJ can't be added or renamed to another VJ's other spelling.** For example, if files spell VJ Junior as "Junior", adding "Junior" as a new VJ is refused with "Files already spell VJ Junior as “Junior”". This stops the duplicates that merging cleans up.

## Recommended features

| Feature | Built? |
| --- | --- |
| Featured VJs, listed first in the app | Built |
| The order VJs appear in the app | Built |
| VJs' social links, shown in the app | Built |
| Merging duplicates, and refusing new ones | Built |
| Deleting a VJ added by mistake | Built |
| Viewers in the last 30 days, per VJ | Built |
| Downloads per VJ | **Not possible yet:** downloads aren't recorded anywhere. A count would need the API to log each download it starts |
| A "verified" badge on VJs' pages | Proposed: a flag, shown next to the name |
| Viewers following a VJ, told of new titles | Proposed: needs a follow table and notifications, a bigger piece |
| VJs uploading with their own sign-in, not a key | Proposed: the strongest next step for the Luganda VJ catalogue, but it needs a VJ role and its own screens |
| Earnings or plays per VJ | Proposed: needs counting plays per title, and decisions about money |

## Decisions to review

| Question | Decision | Why |
| --- | --- | --- |
| What does inactive hide? | The VJ's place in the list and their page, **not their titles or their credit on them** | As asked: "titles stay but the VJ is hidden from browsing". Hiding the credit would show the titles as unknown VJs |
| Merging two VJs who both translated the same film | **Refused**, naming the film | Each film can have only one edition per VJ. Delete or re-credit one of the two first |
| Which bio and photo survive a merge | The VJ who stays keeps theirs. If they have none, they take the duplicate's | It never overwrites what the admin chose |
| Deleting a VJ with titles | Refused. Merge, or make them inactive | A title with no VJ can't stay published |
| Which links | Facebook, Instagram, TikTok, YouTube, X, WhatsApp, website. Each must be `https`, on that site | Links open from the app, so no other sites |
| The editor role may now delete VJs | Granted. A database test checks that a VJ with titles still can't be deleted | Needed for merging and deleting. A VJ's titles still block it |

## What changed

| File | Change |
| --- | --- |
| `migrations/versions/0017_vj_profiles.py` | `vjs.active`, `featured`, `sort_order`, `links`. The app may read them. Admins may delete VJs |
| `app/admin_catalogue.py` | VJs counted by state and viewers. `clean_links`, `update_vj_profile`, `merge_vjs`, `delete_vj`. The other-spelling check on add and rename |
| `app/admin.py` | `GET /admin/vjs/{id}`; `PATCH /admin/vjs/{id}` takes active, featured, sort_order and links; `POST /admin/vjs/{id}/merge`; `DELETE /admin/vjs/{id}`. Changes are audit-logged |
| `app/viewer.py`, `app/viewer_routes.py` | The app's VJ list leaves out inactive VJs and puts featured ones first, then by place. VJ pages carry their links |
| `scripts/copy_to_production.py` | Copies a VJ's links |
| `lib/admin/vjs_view.dart` | The list, the VJ's page, and the dialog with links, featured and place |
| `lib/screens/vj_screen.dart`, `lib/api/catalogue_api.dart` | The app's VJ page shows their links |
| `lib/api/admin_api.dart` | The new fields and calls |
| `lib/l10n/app_en.arb` | 41 new strings |

## Deploying

Run migration **0017**, after 0015 and 0016, before the API.

## How to test it

1. Open **VJs**. Each VJ shows their counts. Type a spelling, such as "junior": that VJ is found.
2. Open a VJ. Their titles are listed, and each opens in the editor.
3. Press **Change this VJ**. Turn on **Featured** and add a Facebook link. In the app, they're first among VJs, and their page has a Facebook button.
4. Press **Make inactive**. In the app, they're gone from the VJ list, and their titles still name them. Press **Make active**.
5. Add a VJ named as another VJ's other spelling: it's refused.
6. On a duplicate, press **Merge into another VJ** and choose the right one. Their titles move, and you land on the VJ who stayed.

## Checks done

- **API:** 829 tests pass, 1 skipped, with 15 new. `ruff check` and `ruff format --check` are clean.
  - `tests/test_admin_vjs.py` (15):
    - links checked, and bad ones refused (6)
    - each VJ's titles counted
    - an inactive VJ leaves browsing but keeps their credits
    - featured first, then the admins' order
    - links on the VJ's page
    - another VJ's spelling refused
    - a duplicate merged into the right VJ
    - VJs with the same film not merged
    - merging checked
    - only a VJ without titles deleted.
  - `tests/test_catalogue.py`: the editor role may delete a VJ only when nothing is credited to them. Deleting VJs was in the list of things the editor role can't do; it now has its own test.
- **App:** 723 tests pass, with 10 new.
  - **VJs (9):** the list with counts and badges; search, filter and sort; a VJ's page with profile, links and titles; making a VJ inactive; merging a duplicate; deleting a VJ without titles; editing links, featured and place, with a bad link refused; adding a VJ and their links; a narrow phone with large text, list and page.
  - **The app's VJ page (1):** links shown, and only https ones.
  - The old VJs list test was updated for the new layout. `flutter analyze` is clean.
- **A layout bug found and fixed:** on a narrow phone with large text, each title on a VJ's page didn't fit its state badge beside it. The badge now sits under the title.
