# OneStep 0.10 Beta — build verification

Functional binary source: [39c9365a511f4f65d7e89967e8d244859a753ef7](https://github.com/sillytira/onestep-ios/commit/39c9365a511f4f65d7e89967e8d244859a753ef7). Subsequent source changes are documentation and CI Dart formatting only.

## Automated evidence

- [Native iPhone build33](https://github.com/sillytira/onestep-ios/actions/runs/44086363333):32 core tests and18 iPhone simulator tests passed, then standard/old-identity bridge/Screen Time physical-device IPAs built. Includes month-end/early recurrence, merge conflicts, real persistence, shared encrypted-backup test vector, and captured Calendar/More/Live Activity layouts. All50 native/core tests pass.
- [Android build15](https://github.com/sillytira/onestep-ios/actions/runs/44086363422):41 portable tests pass. Static analysis has no errors/warnings; seven informational deprecation/import notices remain. Coverage includes encrypted password/tamper handling, independent backup interoperability, merge edit/delete conflicts, exact conflict choices, a local edit arriving during cloud publication, recurrence, calendar buckets, localized labels/private-title preservation, XP/account binding, reminder permissions/icon scheduling and prior planner/family regressions.
- Android actual release-APK emulator smoke: **PASS on isolated retry (job134145134085)**: actual Android API35 release APK launched, More/reminder settings opened, native notification2147483646 posted without precise-alarm access, no invalid_icon or fatal exception. Device screenshots and ANDROID-SMOKE.txt were inspected.. First attempt was blocked by an unrelated Pixel Launcher ANR; OneStep was visible behind the system dialog and no OneStep fatal exception appeared. The failed attempt is not release evidence. The isolated retry uses the same functional source.
- [Isolated PostgreSQL16 service tests](https://github.com/sillytira/onestep-ios/actions/runs/44081625793):full001–006 upgrade suite followed by007 authorization/CAS/cohort checks. Covers own-user encrypted snapshot access, stale-revision rejection, owner-only delegation/revocation, per-capability denial, moderator child/email redaction, owner protection, suspension across old RPCs/direct reads, private implementation denial, audited/idempotent adjustments, owner-only audit access, child/ranking exclusions and beta/production earning separation. Synthetic fixtures only; no production changes.

Total:91 app tests, plus PostgreSQL tests and the separate layout/emulator smoke flows. Tests are evidence for their cases, not proof of all physical-device conditions.

## Package checks

Three arm64 IPAs report0.10.0/build33 and expected identifiers/extensions. All six localization bundles are present. Normal/bridge each embed Live Activity; Screen Time additionally embeds the DeviceActivity monitor. GitHub artifact digests and individual IPA SHA256 files verify. IPAs are unsigned and still require the correct Apple team/profiles.

Final Android meow.tira.onestep reports0.10.0-beta/build15, label OneStep Beta. Official apksigner v2/v3 verification passes; certificatead35a758e1304c98d1574b7849d25e2d040379bd7a1cfc391a2349f2436bf312 matches the prior delivered APK. All96 non-signature members match the CI-tested APK. The compiled ic_notification resource remains present. Signed APK SHA256:1b77da69bea9d7da290f3699d8f7028fd67a16c15f560ec755281a2d2c667ed6.

Public source/private-material scans reject privileged/service-role keys, session JWTs, owner invitation plaintext and signing credentials. Only the expressly approved public connection defaults ship. The final source archive includes hidden GitHub workflows and excludes private/work directories. Package/source manifests and outer bundle SHA256 are verified separately; see the included reports and SHA256SUMS.txt.

## Visual inspection

Final native Calendar/More renders and existing detailed Live Activity layouts are simulator-rendered UI. Android Now/More/Calendar widget previews use a synthetic planner; *-device.png captures come from the actual release APK on an Android emulator. Layouts were viewed for legibility and overflow. Draw-hierarchy captures may omit system glass compositing and are not installed Lock Screen delivery evidence.

## Live setup and remaining acceptance

Live service001–005 is the last known baseline. **006/007 are not deployed.** Windows Edge automation returned GetCursorPosAccessDenied; the owner explicitly chose to restore access later. Included ready migrations must be applied only if missing, in order, through the authenticated project. Online new-economy/XP, encrypted cloud sync and moderator tools need that service upgrade. No online activation or signed-in family/moderator acceptance is claimed.

The owner confirmed basic tasks, reminders, routines and updating work. New two-device encrypted import/sync, timezone/DST recurrence, real moderator revocation, family approval/PIN flows and genuine Apple Screen Time/widget/Live Activity behavior remain in ACCEPTANCE-010.md and Notion. Core language support is Beta, with English fallback for detailed service/admin text. Local planner/recovery files are not a newly encrypted database. Windows/Linux and optional companion binaries were not rebuilt in this release. Earlier delivered bundles remain unchanged.
