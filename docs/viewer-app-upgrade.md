# Viewer app upgrade

The Flutter client adds Filter, genre shelves, a shared responsive poster grid, movie and series detail layouts, and a viewer Account hub. Android and web keep their existing sign-in, checkout and media entry points. Android's Downloads shortcut and the Account row share the same installation library. Downloaded MP4 files remain in the viewer's Downloads folder.

The Account screenshots use the same signed-in test viewer at 390 × 844 logical pixels. [Before](viewer-upgrade/account-before.png) · [After](viewer-upgrade/account-after.png)

## API prerequisite

The matching API provides catalogue genres and the signed-in viewer's notifications, history and deletion status. Migration `0009_account.py` follows `0008` and adds row-level security for all three account tables. Apply it before serving the new API in an approved environment. The player reports progress for an authorized item. An unused playback grant, an admin preview or opening a saved MP4 in another player does not add a title to the viewer's history.

## Settings and release dependencies

| Feature | Available in this change | Needed for release |
| --- | --- | --- |
| In-app notifications | The inbox derives events from the viewer's payments, passes and removed devices. Read marks persist per account. | Migration 0009 and the matching API. |
| Android push | Settings reads the OS notification state. Delivery and opt-in stay unavailable. | A configured push provider, client registration and token refresh, account-scoped suppression on opt-out or sign-out, and a physical-device delivery check. |
| Android App Lock | The installation can require the system biometric or device credential prompt. The lock covers launch and return after a minute away. | Check enrollment changes, OS prompt cancellation, cold start and returning from browser sign-in on a phone. Check offline opening of a downloaded file there as well. |
| Share and account recovery | Sharing uses `PUBLIC_APP_URL`. Password reset opens `/reset` on the configured auth pages. | Use the public addresses for the target environment. |
| Ratings and privacy | Settings can open the configured links. | Supply the verified VeloraUG listing in `PLAY_STORE_URL` and an approved policy in `PRIVACY_POLICY_URL`. |
| Permanent deletion | The protected development flow checks recent authentication for the same account, records pending work and supports retry. The production API has no identity deleter and the feature flag defaults off. | Approve the handling of unused membership time, refunds, billing and audit retention. Supply a provider integration for identity deletion and session revocation, verify its signed authentication-time claim, and test recovery from each partial failure with disposable accounts. |

Account deletion in the development tests retains payments and passes for reconciliation. That test behavior is a proposal pending approval. The existing ownership decision for downloaded files applies independently.
