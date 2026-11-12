# OneStep 0.5 — verified release

Verified November 12, 2026. Eleven installable packages are delivered. Native iPhone version 0.5.0 build 15 includes the main new-ID and old-ID migration-bridge IPAs, each with one Live Activity/shortcut-widget extension. Portable main and all six phone companions are version 0.5.0 build 10. Package IDs remain meow.tira.onestep and its .bank/.kids/.parent variants; the bridge retains tech.sillycat.onestep.

## What changed

- Main-instance public connection defaults ship in all clients; the URL/key entry step is removed. Only the approved publishable key is public. Authentication/RLS and server-controlled roles still enforce access. Privileged keys, passwords, owner invitation plaintext, private Android keystore, and signing password remain outside public source and archives.
- Versioned non-executable content packs refresh from a pinned public HTTPS feed, validate size/schema/revision/app compatibility/times/colors, and persist offline. Users review and add packs; private edits/history are never automatically replaced. Native executable updates/signing expiry remain separate.
- Added today-only routine undo/rescheduling, portable guided sequence progression, grouped same-time task/routine reminders, reminder coverage, shortcut widgets, and Live Activity Done/Snooze with exact-action/day validation. Time Sensitive routines are gated by system/provisioning access with ordinary fallback.

## Build and test evidence

- [Final main native build](https://github.com/sillytira/onestep-ios/actions/runs/43185476985): 23 Swift core tests and 11 native simulator tests passed. New tests exercise LiveActivityIntent completion, repeated/stale actions, snooze, previous-day routines, archived tasks, content validation/import, history preservation, and reminder grouping. Both unsigned device IPAs built.
- [Portable analysis/tests and builds](https://github.com/sillytira/onestep-ios/actions/runs/43183201446): 14 tests passed, Android/Windows/Linux built, Windows launch smoke and Linux AppImage extraction/GUI launch succeeded. Two existing Radio API deprecation messages were informational; no analyzer errors. Linux screenshot inspected. A local Windows hidden-process launch check passed outside the shell sandbox; no targetable window was exposed for local GUI inspection.
- [Six companion builds](https://github.com/sillytira/onestep-ios/actions/runs/43183201300) all passed.
- [Dedicated Linux packaging](https://github.com/sillytira/onestep-ios/actions/runs/43183201525) passed.
- [Backend authorization tests](https://github.com/sillytira/onestep-ios/actions/runs/43088238748) from the unchanged deployed schema cover private family/ledger access, invite gating, owner binding, parent-only approvals/unlink/PIN setup, and child privacy. Live anonymous ledger/enrollment-table reads again returned401 permission denied after the public connection key was shipped. No live owner account was created by tests.
- [Public source scan](https://github.com/sillytira/onestep-ios/actions/runs/43185477172) passed. Local source/project validation also passed.

Total: **48 app tests**, plus the backend authorization tests. Actual signed-phone/family acceptance remains pending.

## Content-only update evidence

[Revision 2 publication](https://github.com/sillytira/onestep-ios/commit/96a31b54ea256bd086d4b4b7214fd660c40489a6) changed only content/catalog.json after the first 0.5 builds. Only the [source scan](https://github.com/sillytira/onestep-ios/actions/runs/43185137712) ran; no new native/portable binary build was triggered. An HTTPS fetch from the exact client feed returned 200, revision 2, and 3 packs. This proves publication/delivery without a new IPA; user-device cache/UI acceptance remains in ACCEPTANCE.md.

## Package inspection and Android signing

Downloaded artifact ZIP digests matched GitHub metadata. Original packages matched their CI checksum manifests. Independent parsing verified iOS plists/arm64 binaries/extension counts, APK binary manifests/build 10/three ABIs, Windows PE x64/Tira-OneStep.exe, and Linux ELF x86-64/type2. Public connection defaults were found in the inspected compiled native/portable payloads. Owner invitation and private Android signing files/password were absent from inspected public package contents.

Android inspection found that the old debug-keystore cache never saved its target file; certificates differed between 0.4 and 0.5. The delivered 0.5 APKs were then signed locally with a saved private RSA-3072 key using official Android apksigner. All four signatures verified with APK Signature Schemes v2/v3; all share certificate SHA256 ad35a758e1304c98d1574b7849d25e2d040379bd7a1cfc391a2349f2436bf312. An independent comparison of 129 non-signature ZIP members per APK confirmed their application payloads match the tested CI builds. Final SHA256SUMS describes these newly signed APKs, not the original test-signed artifacts.

The old private keys were not retained by CI and cannot be recovered from certificates. Therefore existing 0.4 Android installations require a verified backup and one-time signing migration, not an in-place update. Future delivered APKs must use the saved new key. The broken cache is removed; optional CI-secret configuration and local signing script are provided. The private release key was not uploaded to GitHub. Optional CI configuration was checked locally with synthetic material.

## Source revisions and remaining boundaries

Final native functional/test source: [f14967e](https://github.com/sillytira/onestep-ios/commit/f14967e8ed14c23bbca1641a8b5489ecb26b625f). Portable/companion binary source: [6582610](https://github.com/sillytira/onestep-ios/commit/6582610824c968dde08a4e000b64477652bb6447). Later source retains CI formatting/lock, documentation, content revision 2, and signing-tool/workflow corrections; Android payloads are unchanged by signing.

See PENDING.md for owner enrollment, signed-device checks, Apple Family Controls/Time Sensitive/shared-container prerequisites, and future online merging/encryption scope. No OS TikTok shielding, point spending, unrestricted database administration, arbitrary executable hot patching, or signing-expiry bypass is claimed.
