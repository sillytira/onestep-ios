# OneStep content updates — 0.5

Install the 0.5 native application once to add this updater. Afterwards, public routine packs, schedules, wording, and step colors can refresh inside that installed application without replacing its IPA/APK/EXE/AppImage. New native functionality still requires a new application build and, on iOS, signing. The updater cannot extend an Apple signing profile's expiry.

## Using updates

Native iPhone: Settings → Content updates and routine packs. Android/Windows/Linux: Your space → Content updates. The main planner checks the public feed on launch by default. Disable automatic checks in that screen if desired. Manual checking remains available. Connection/account screens already use the main OneStep instance; users no longer paste project keys.

The library shows its revision, pack description, exact steps, times, and colors. Add a pack explicitly after reviewing it. Existing tasks, history, and edited routines are preserved. A pack ID is recorded in planner backups to prevent accidental duplicate imports. A newer library does not silently replace a pack you previously edited. Downloaded valid content remains available offline; the private planner works even if no content has ever been downloaded.

## Publishing without an app rebuild

The owner can edit `content/catalog.json` in the GitHub repository and commit a content-only change to main. Increase `revision` on every publication, including a correction or rollback. Keep `format: OneStepContent`, `schema: 1`, and a compatible `minAppVersion`. Content-only changes do not trigger the binary build workflows. Users receive the new library on the next check; no IPA registration/signing is consumed.

Each pack has a stable ID, title, description, and up to 30 steps containing title, hour, minute, and one supported color. The document is limited to 64 KiB and 50 packs. The clients reject unsupported schema/app versions, duplicate IDs, invalid times/colors, oversized documents, and revisions older than their cached revision. Fetching uses a fixed HTTPS feed, bounded timeouts, and rejects redirects. Failed checks retain the last valid cache.

This is a data update format. It does not load scripts, native libraries, HTML, arbitrary links, or executable code. It cannot grant admin privileges, change family membership, create points, change a child's server role, or disable parent authorization. The GitHub repository and its maintainers are trusted publishers of public pack data. Protect repository write access accordingly. No account tokens or private planner data are sent to the feed.

## Application updates and parental controls

The existing GitHub-release checker links to native beta downloads. Install an updated IPA over the existing app using the same signing account and identifier; do not uninstall. A new executable cannot be installed by replacing the signed app from inside itself. Roblox-style content delivery likewise relies on capabilities already present in an installed engine; this format updates the capabilities OneStep already understands.

Live Activity Done/Snooze actions are implemented in the application process and validate the exact referenced task/day before changing it. The system may require device unlock. Home Screen widgets reuse the existing extension and provide private-data-free shortcuts. A widget showing private task data needs a provisioned shared App Group and is not claimed by this free-signing beta.

Time Sensitive routine support is gated on the signed app's system authorization. Builds without that access use ordinary alerts. This beta does not assert that a free Apple profile provides Time Sensitive provisioning. Critical Alerts are not enabled.

Screen Time app shielding still needs Apple's Family Controls capability and an appropriate provisioning/distribution route, plus authorization on the child's device. Creating a Linux server does not provide those Apple permissions. Point-funded app-time redemption must be integrated with a verified shield/unlock lifecycle before advertising that TikTok is locked or unlocked. No bypass or fake enforcement is included.

Official references: [public Supabase keys](https://supabase.com/docs/guides/getting-started/api-keys), [Family Controls entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement), [interactive widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [iOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios).
