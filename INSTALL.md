# Install OneStep 0.7 beta

## Main iPhone app

If you already installed meow.tira.onestep 0.3, sign/install the new main IPA over it with the same Apple account and identifier settings. Export a backup first. Keep its Live Activity extension. Do not uninstall to update.

If your existing app is the older tech.sillycat.onestep identity, first sign/install the migration-bridge IPA over that app using its original signing settings. Export a JSON backup outside the app through Now → settings → Backups and Wi-Fi transfer. Verify the backup is accessible, then install the normal new-ID IPA and import it. New identity means new permissions and a separate sandbox. Never delete the old app before exporting and checking your data.

An unsigned IPA must be signed by your installer. Use your already working AltStore/Sideloadly flow and keep the extension. Official guides: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows and https://sideloadly.io/ . Free Apple expiry and app/App-ID limits still apply. Install only the roles needed on each phone; the main planner, Bank, Kids, and Parent are distinct app identities. An iOS companion has no extensions; the main app and bridge each have a Live Activity extension. Native code updates still require a new signed installation.

## Bank / Kids / Parent companions

Install the appropriate companion IPA on iPhone (after signing) or APK on Android. IDs are meow.tira.onestep.bank, meow.tira.onestep.kids, and meow.tira.onestep.parent. Use the same hosted service across clients and the same app email/password when viewing the same account. Parent and child accounts must be different. Installing a different app does not change the server role of an account.

The main OneStep service is already configured in every app; sign in directly without copying a URL or public key. Never enter a database password or service-role/secret key. The owner must create the app account once with their private single-use enrollment key and configured owner email, choosing their own app password. The Supabase website account is separate. Later devices just sign in. The app owner is meow; tira is reserved. Do not put the private setup/key files into a source ZIP or public repository.

The owner then opens Application admin to generate email-bound Parent/Kids beta keys. A parent creates a family and shares a separate ten-minute family invitation with the child. Parent assigns tasks/rewards; child requests approval; parent approves once. See FAMILY.md for offline parent-code setup, account linking, and privacy.

## Android main app

Install the APK through your normal Android installer. Package is meow.tira.onestep. Enable notifications and precise alarms under Your space; inexact alarms are the fallback. Version 0.5 and later delivered APKs use the permanent private OneStep signing key. Earlier 0.4 APKs used unrecoverable per-run test keys, so this is a one-time signing migration: export the old planner and verify the backup before uninstalling an old Android build. Import after installing the new APK; sign in again to online services. Future APKs must retain the new certificate. Do not uninstall the only copy of your data. See ANDROID-SIGNING.md.

## Windows / Linux main app

Windows: extract the complete ZIP, then run Tira-OneStep.exe. Display name OneStep. Keep its DLL/data folders together. Linux: use the x86-64 AppImage on a compatible GTK3 desktop, make it executable, and launch. --appimage-extract-and-run is an option without FUSE. Desktop notifications/timers require the app to remain running. Secure account sessions require the OS credential/keyring service. Bank/Parent/Kids service sections are inside the main desktop app; separate desktop companion packages are not provided.

## Local files and Wi-Fi

Private planner transfers work without accounts or a server. Keep both devices open on the same private IPv4 Wi-Fi. Sender creates a ten-minute pairing code in Data/devices; receiver pastes it, previews the snapshot, and confirms replacement. A recovery backup is saved first. Export both devices before combining separate edits: this is a snapshot copy, not automatic conflict merging. JSON exports are readable private data. The same format can be copied through Files/USB. Online login and roles are not transferred by planner backups.

## Verify on your devices

Compare package SHA-256 with the delivered checksum manifest. Confirm restart persistence, migration/update retention, offline locked-device reminders, follow-up cancellation, next-day routine reset, timer pause/expiry, and Live Activity. For family services verify owner enrollment, parent-child linking, single approval credit, private Kids identity, parent-only unlink, and a previously synced parent code with the backend unreachable. Cloud builds do not establish those physical-device outcomes.

## Enable content updates once

Install this 0.5 application over the matching existing identity to add the updater. Future routine-pack/content revisions can refresh inside it without another IPA/APK installation. New native code still needs an application update; Apple signing expiry is unaffected. See UPDATES.md.

## Optional Apple Screen Time variant

The ordinary IPA keeps its existing Live Activity extension. The separately named screen-time IPA uses the same main bundle ID, adds a DeviceActivity monitor extension, and requires Family Controls plus a shared App Group in the signing profiles. Install one main variant, not both. This is not promised to work with free Personal Team signing. Bank/Kids/Parent Flutter companions do not contain Apple blocking extensions. Read SCREEN-TIME.md before choosing this variant. Back up before changing variants. Android updates from the delivered 0.5 APKs reuse the permanent certificate; no uninstall should be needed.

## Version 0.7 account and navigation repair

Back up, then install over the same app identity and signing account. Bank is now a main iPhone tab and a desktop sidebar destination; Notes/History/settings are in More on iPhone. Old manual connection settings no longer override the main service. If a cached session needs recovery, open Bank → Account → Reconnect this account and enter that account’s password. This does not unlink a child. Only the user enters real credentials. The separate Apple Screen Time provisioning requirement is unchanged.
