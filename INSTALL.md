# Install OneStep beta on iPhone using Windows

## Get the IPA

Open https://github.com/sillytira/onestep-ios/actions and choose a successful **Build iPhone beta** run. Download its `OneStep-0.1.0-beta-N` artifact ZIP on Windows, extract it, and find `OneStep-0.1.0-beta-N-unsigned.ipa`. An unsigned IPA needs AltStore signing before it can run.

Optional integrity check in PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath '.\OneStep-0.1.0-beta-1-unsigned.ipa'
```

Compare it to the matching `.sha256` file included with the download.

## Install

1. Follow AltStore's current official Windows setup guide: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows . Install the Apple components it specifies and AltServer, then install AltStore Classic on the iPhone.
2. Enable Developer Mode on the iPhone if prompted. Use the same Apple account for AltStore and later OneStep updates.
3. Keep AltServer running and reachable from the iPhone as described by AltStore. Transfer the IPA to the iPhone's Files app using a method you already trust.
4. Open AltStore → My Apps → **+**, then select the OneStep IPA. Let AltStore sign and install it.
5. Open OneStep. Tap the bell in **Now**, choose **Enable reminders**, and grant permission.
6. Add a task due two minutes ahead with **Remind me** enabled. Lock the phone and verify the notification. Tap it to return to the task.

Enter Apple credentials only through AltStore/Apple's normal signing flow. This project never needs your password, certificates, or private keys.

## Update without changing app identity

Build the next IPA with a higher build number, then install it through the **same AltStore installation and Apple account over the existing OneStep app**. Keep the app ID `tech.sillycat.onestep` unchanged. Do not delete OneStep first: deleting it also deletes its local data, and this beta has no backup/export feature.

Updates still need signing. The app has no extensions, so only its main App ID is needed in addition to AltStore's own IDs. Building source on CI does not sign the app or register new App IDs. Free-account expiry and AltStore's device/app limits still apply; this is not a signing-limit bypass.

With a free account, refresh the app through AltStore before its seven-day expiry. Keep AltServer running and reachable; offline app use does not make signing refreshes offline. See https://faq.altstore.io/altstore-classic/your-altstore and https://faq.altstore.io/altstore-classic/app-ids .

## Use reminders offline

After granting permission, already queued notifications work without a server. Open OneStep regularly to extend the queue. Check **Now → bell → Scheduling coverage** for its exact coverage. Focus, silent mode, and notification settings may silence or delay ordinary alerts.
