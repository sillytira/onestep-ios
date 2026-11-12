# OneStep 0.4 family beta — build verification

Verified on November 12, 2026. Compiled binaries are delivered; physical-device installation and real owner enrollment remain acceptance checks.

## Packages and source

- Main native iPhone: 0.4.0 build 13, arm64, iOS 26+, meow.tira.onestep plus one meow.tira.onestep.liveactivity extension. Old-ID migration bridge retains tech.sillycat.onestep and its extension. Both are unsigned IPAs for signing by the user's installer.
- Main Android: 0.4.0 code 9, meow.tira.onestep, arm64-v8a/armeabi-v7a/x86_64.
- Bank/Kids/Parent iPhone companions: 0.4.0 build 9, arm64, meow.tira.onestep.bank/kids/parent, no extensions.
- Bank/Kids/Parent Android companions: 0.4.0 code 9, the same corresponding identifiers and three ABIs.
- Windows: x64 PE Tira-OneStep.exe with required DLL/data files in the distribution ZIP. Extract the complete archive.
- Linux: x86-64 type-2 AppImage, packaged and launch-checked on Ubuntu 22.04.

Native binary source: [3df798e](https://github.com/sillytira/onestep-ios/commit/3df798eb83925be9b3619f8b6f486d0e23de8614). Final portable/companion source: [527d3eb](https://github.com/sillytira/onestep-ios/commit/527d3eb06e7889d47d75e0e5e84fee40da761a94). The latter changes three portable explanatory strings, including the About version and private-progress versus approved-points explanation. The delivered source additionally retains CI-formatted Dart files, the resolved dependency lock, and current documentation; no functional changes follow the tested builds.

## Observed checks

- [Native build/tests and both IPAs](https://github.com/sillytira/onestep-ios/actions/runs/43091619862): 18 Swift core tests and 9 native simulator tests passed, including disk reopening and an independent PBKDF2 parent-code vector. Both unsigned device packages built successfully.
- [Final portable build](https://github.com/sillytira/onestep-ios/actions/runs/43165566683): static analysis, 8 tests, Android packaging, Windows launch smoke check, Linux AppImage extraction/GUI launch/screenshot all passed. Inspected the Linux Now preview for readable text and clear progress labeling.
- [Final companions](https://github.com/sillytira/onestep-ios/actions/runs/43165566680): all six iOS/Android role builds passed.
- [Backend authorization tests](https://github.com/sillytira/onestep-ios/actions/runs/43088238748): migrations 001–004 tested using synthetic users; family isolation, exactly-once approval, no self-credit, invite gating, owner binding, reserved names, child privacy, and parent-only unlink/PIN setup passed.
- [Public source scan](https://github.com/sillytira/onestep-ios/actions/runs/43165566719) passed. Local source scan also passed.
- Downloaded artifact ZIP digests matched GitHub metadata; every delivered binary checksum matched its build manifest. Independently parsed iOS binary plists/Mach-O, Android binary manifests/ABIs, Windows PE headers, and AppImage ELF/type signatures.
- Scanned release ZIP/IPA/APK members and raw deliverables against the actual private project/enrollment keys without logging them: no matches. Private setup/enrollment files are outside the public source/release directories.
- With the user's explicit approvals, deployed tested private family/beta/parent schema and owner-invitation hash, then disabled email confirmation. Live anonymous API calls to the ledger and enrollment table returned permission denied. The real owner account has not been created by automated tests.

## Remaining acceptance and limits

Use ACCEPTANCE.md and FAMILY.md for the real-device flow. The user must choose their own app password and consume the private owner invitation once. A previously synced parent verifier is necessary for offline authorization. Code revocations reach disconnected devices when they reconnect.

OS app blocking, Screen Time entitlements, app-time redemption, continuous planner sync, and unrestricted Supabase database administration inside the apps are not delivered. Child sign-out gating cannot prevent uninstall/reset or modified clients. Ordinary notifications obey OS permissions and policy. Free Apple signing expiry and app/App-ID limits still apply; install only the companions needed on each device. Core planner use and manual encrypted local-Wi-Fi transfer need no server; online family actions need the managed service.
