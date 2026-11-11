# Install OneStep 0.3 beta

## iPhone: migrate safely

1. Download a successful Build iPhone beta artifact from https://github.com/sillytira/onestep-ios/actions . Check the IPA SHA-256 against the adjacent checksum file.
2. If you already use the old tech.sillycat.onestep app, first sign/install the **migration-bridge** IPA over it, with the same Apple account and bundle-ID settings used for the existing installation. Keep its Live Activity extension. Do not uninstall first.
3. Open Now → settings → Backups, Wi-Fi transfer, and accounts → Export backup. Save the JSON outside the app in Files. Verify it is accessible; an additional copy on your PC is recommended.
4. Sign/install the normal IPA with the new **meow.tira.onestep** ID, then import that JSON. Review the preview and confirm. Check tasks, routines, notes, and history before removing the old app. Never delete your only copy to free a signing slot.
5. Allow notifications in the new installation, because permissions belong to the new app identity. Test a task due two minutes ahead while locked and offline. Sign the Live Activity extension as well as the main app.

Use your existing successful installer, AltStore or Sideloadly. Official guides: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows and https://sideloadly.io/ . Do not strip the extension. Free-account app/App-ID limits and signing expiry still apply. Both bridge and normal app have an extension, which can affect available slots. Export before managing those slots. Signing/refreshing requires Apple connectivity; ordinary app use and queued reminders work offline. The app cannot refresh its own Apple provisioning profile.

After migration, future updates use the same new bundle ID and signing settings and install over the app. Uninstalling deletes local data. Export backups regularly.

## Android

Download OneStep-0.3.0-beta.apk from the successful Android artifact. Permit installation through your normal Android installer. Package ID is meow.tira.onestep. In Your space, enable notifications and precise alarms; without precise-alarm permission delivery falls back to inexact scheduling. Check an offline locked-device reminder.

This initial beta uses a CI beta signing key cached between builds. It is not yet a permanent privately managed release key, so seamless future in-place updates are not guaranteed if the cache expires. Export before updating; do not uninstall to resolve a signing mismatch until your data is safely backed up. See PLATFORMS.md for release-key configuration.

## Windows

Extract the complete Windows ZIP to a folder, then run **Tira-OneStep.exe**. Display name: **OneStep**. Keep its DLLs and data directory beside the executable. This is an unsigned portable distribution, not a Microsoft Store package. Local data is kept in the current Windows user's application-support directory. Notifications and timers require the app to stay running. Private Wi-Fi transfers may require allowing the app through the private-network firewall; no public-network or router port forwarding is needed.

## Linux

Use the x86-64 AppImage on a compatible GTK 3 desktop (built on Ubuntu 22.04). Make it executable, then launch. If FUSE is unavailable, use --appimage-extract-and-run. Timers and banners require the app to stay running and a desktop notification service. Keep backups outside the app's data directory.

## Transfer without a server

Both devices: join the same private IPv4 Wi-Fi network and keep OneStep open. Sender: open Data/devices, confirm its LAN address, create the 10-minute code, and share it privately with your receiver. Receiver: paste it, receive, inspect the snapshot preview, then confirm replacement. A recovery copy is saved first. Leaving/backgrounding the sender stops sharing. Transfer is encrypted; the code is its temporary key. Copy only between trusted devices. It is a one-way snapshot, not automatic merging; export both devices if they contain separate edits. The same JSON format supports transfer through Files/USB.

An internet login is optional and independent of LAN pairing. See PLATFORMS.md for Supabase setup. Signing in does not upload planner contents or synchronize devices.
