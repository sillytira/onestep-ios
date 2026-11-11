# OneStep — 0.3 beta

An offline task and routine planner with one next action, readable cards, and large controls. iOS uses SwiftUI and Liquid Glass. Android, Windows, and Linux use a shared Material 3 client. Core use needs no server or account.

## This release

- Tasks, notes, daily routine records, local reminders, focus timers, and item colors.
- Versioned JSON backup/import with a preview and automatic recovery copies.
- Encrypted manual snapshot transfer over private Wi-Fi, with expiring pairing codes.
- User-written microsteps, daily/weekly tasks that advance after completion, search/list names/pin/archive, duration-timer pause/resume, and bounded reminder preferences.
- Separate notes collection; native iOS Live Activity retained.
- Optional configurable Supabase email-code identity. A hosted project and email-delivery configuration are required; planner data is not uploaded and cloud sync is not implemented.

Read [PLATFORMS.md](PLATFORMS.md) for exact platform support, account setup, architecture, signing, and limitations. Native code updates still need a newly installed package.

## Important identity migration

The requested new Apple/Android ID is **meow.tira.onestep**. The old iOS app used tech.sillycat.onestep and cannot automatically share its sandbox with the new ID. The iOS workflow also builds an **old-ID migration bridge** with backup export. Install that bridge over your old app first, export your backup, then import into the new-ID app. **Do not delete your old app before exporting and verifying its data.** See [INSTALL.md](INSTALL.md).

Windows displays **OneStep**, with **Tira-OneStep.exe** in the complete distribution folder. Linux ships an x86-64 AppImage. Source alone is not a compiled delivery; use successful workflow artifacts and the release verification report.

## Build and verification

GitHub Actions builds iOS on macOS/Xcode 26.6, Android on Linux, Windows on Windows, and Linux on Ubuntu 22.04. Builds run from source changes on main and support manual dispatch. Every iOS build runs Swift core and native simulator tests before device packaging. The portable workflow runs analysis and behavior tests before platform builds. No Apple credentials are used.

For iOS: run node scripts/generate-project.mjs, node scripts/generate-icon.mjs, node scripts/validate-source.mjs, swift test, and xcodebuild test with the shared OneStep scheme on an iPhone simulator. Build the IPA with BUILD_NUMBER=5 bash scripts/build-ipa.sh. Override APP_BUNDLE_ID=tech.sillycat.onestep and IPA_SUFFIX=-migration-bridge for the old-ID bridge.

For other platforms: install Flutter 3.38.5 and Node 22, run node portable/tool/bootstrap.mjs from the repository root, then flutter pub get, flutter analyze, flutter test, and flutter build apk/windows/linux from portable. Native platform files are generated; application source and the dependency lock are retained. See portable/tool/appimage.sh for AppImage packaging. Android permanent private release signing is not configured automatically.

## Planned, not active

Spendable points, public rankings, parent PIN controls, iOS app shielding, online planner sync, custom full-database encryption, and a separate points banking companion are not active features. The progress count is not a points balance. Family Controls requires Apple authorization/entitlements and suitable signing. No third-party screenshots, personal data, signing keys, or account secrets belong in this repository.
