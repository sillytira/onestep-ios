# Permanent Android signing identity

The delivered 0.5 APKs use one saved private RSA-3072 signing identity for all four applications. It is separate from Apple signing. The public certificate SHA-256 fingerprint is `ad35a758e1304c98d1574b7849d25e2d040379bd7a1cfc391a2349f2436bf312`. The private keystore and its password are outside this repository and every public archive. Back them up privately; they must be reused for future Android updates.

## Existing 0.4 Android installs

The previous CI cache targeted a keystore path that did not exist. Logs confirmed no key was saved, and inspection found different certificates between 0.4 and 0.5 and between companion jobs. The erased runner keys cannot be recovered from the APK certificates. Replacing the application's certificate is not a way to preserve update compatibility without the old private key.

Export the old Android planner to JSON and verify the file is readable before removing an old Android installation. Install the new permanently signed APK, import the backup, and sign in again to family services. Online family links/points remain server-side; previously cached offline parent verifiers need a fresh authorized setup/sync. Do not delete the only copy of planner data. Once on this new identity, future updates signed with the same saved key and higher version code can install over it, subject to ordinary Android rules.

## Future builds

Raw CI builds without signing secrets use a test identity and are not the official signed release packages. The broken cache has been removed. There are two supported signing routes:

1. The repository owner can configure GitHub Actions secrets `ONESTEP_KEYSTORE_BASE64` (base64 of the saved PKCS12 file) and `ONESTEP_SIGNING_PASSWORD` (its password). The optional configuration step writes the key only to runner temporary storage, masks the password, and selects the private signing config with alias `onestep`. These secrets have not been uploaded automatically. They are privileged signing material and must never be public.
2. Download the built APKs and run `scripts/sign-android.ps1` using a compatible Java runtime, the official Android SDK `apksigner.jar`, and the private key/password-file paths. The script signs each APK in the selected directory and runs `apksigner verify` before replacing it. Never print the password. Regenerate package checksums after signing; an original CI checksum describes the original test-signed artifact, not the newly signed APK.

The release workflow verified original artifact digests, then signed and verified the delivered APKs with Android's official tool. Independent comparison confirms their application payloads match the tested APKs; only signing metadata changed. Existing test-signed 0.4 APKs are deliberately not represented as in-place compatible.

Official instructions: [apksigner](https://developer.android.com/tools/apksigner) and [sign your app](https://developer.android.com/studio/publish/app-signing).
