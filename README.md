# OneStep — 0.6 family beta

An offline task/routine planner with a clear Now screen, microsteps, notes, recurring tasks, local reminders, focus timers, JSON backups, and encrypted private-Wi-Fi snapshot transfers. iOS remains native SwiftUI with Liquid Glass and a Live Activity; Android, Windows, and Linux use Material 3. Core planner use needs no account, internet connection, or server.

Optional OneStep Bank, OneStep Kids, and OneStep Parent phone apps share the same hosted rewards account. The main app keeps its own Bank section. Parents assign fixed-reward family tasks and approve points once; children cannot self-credit or unlink their family. Points cannot be purchased with real money. Version 0.6 adds bounded personal task rewards and an optional native Apple Screen Time build; provisioning and signed-device acceptance remain required.

Read [FAMILY.md](FAMILY.md) for beta enrollment, private runtime setup, owner/admin access, reserved handles, child privacy, parent offline codes, and exact limitations. Kids accounts display email only and are excluded from public rankings. Normal/parent users can set a handle and opt in. Owner enrollment installs meow; tira remains reserved and unused.

The main-instance URL and its explicitly approved publishable client key ship in source and binaries, so account setup requires no manual connection entry. Authentication and RLS enforce access. Secret/service-role keys, real session JWTs, private keys, passwords, and owner enrollment plaintext remain forbidden in source and archives. Clients keep sessions in platform secure storage. Private setup/enrollment material must be delivered separately and never committed. Run node scripts/check-public-source.mjs before uploading source.

## Build

GitHub Actions builds the main IPA on macOS/Xcode 26.6, portable Android/Windows/Linux clients on their respective runners, and Bank/Kids/Parent iOS+Android variants using Flutter 3.38.5. Core/native/portable tests and static analysis precede packaging. PostgreSQL CI checks beta gating, reserved names, parent approval, role isolation, idempotency, and child unlink protections. A successful source upload alone is not binary delivery or physical-device verification.

Native: node scripts/generate-project.mjs, node scripts/generate-icon.mjs, node scripts/validate-source.mjs, swift test, then xcodebuild test for the shared OneStep scheme on an iPhone simulator. Build unsigned device IPA with BUILD_NUMBER=N bash scripts/build-ipa.sh. APP_BUNDLE_ID=tech.sillycat.onestep and IPA_SUFFIX=-migration-bridge produce the old-ID export bridge.

Portable: node portable/tool/bootstrap.mjs, then flutter pub get/analyze/test and flutter build apk/windows/linux in portable. For a companion set ONESTEP_ROLE=bank, kids, or parent before generation and pass --dart-define=ONESTEP_ROLE=ROLE to Flutter. iOS companions use flutter build ios --release --no-codesign and package the generated Runner.app. Generated platform projects are reproducible; application source and dependency lock are retained.

See [INSTALL.md](INSTALL.md), [PLATFORMS.md](PLATFORMS.md), [KNOWN-LIMITATIONS.md](KNOWN-LIMITATIONS.md), and the delivered verification report. Main Apple/Android ID stays meow.tira.onestep. Never delete your only planner copy to free a signing slot.

## Version 0.5 additions

Main-instance connection is automatic. Content packs update inside installed apps without a binary update; see [UPDATES.md](UPDATES.md). Added routine Undo, today-only rescheduling, portable guided sequences, grouped same-time reminder banners, Home Screen shortcuts, and Live Activity actions. Apple entitlement/provisioning and real-device acceptance constraints remain explicit.

## Version 0.6 additions

Normal/parent accounts can enroll private tasks for 0–100 points each, with server anti-spam checks and daily caps of 20 counted tasks/500 earned points. Weekly rankings offer tasks or earned points and exclude children. See [REWARDS.md](REWARDS.md). The separate Screen Time IPA includes Apple FamilyControls, ManagedSettings, and DeviceActivity integration for individual or family authorization, point-funded unlocks, and an opt-in private widget. See [SCREEN-TIME.md](SCREEN-TIME.md). Migration 005 is deployed to the main instance after approval; fresh projects apply migrations 001–005 in order.
