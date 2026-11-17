# OneStep0.10.1 Android/Windows verification

Functional source84e257086f797e200e8afff749ff7258e33132d4. Main native Apple0.10/build33 is unchanged; no Apple build ran for this patch.

The shared task/routine/note editor now has no AppBar Save action and retains one bottom Save with saving/error states. Phone tests verify one Save, visible blank-title validation and successful saving; the desktop test opens the real Home editor, scrolls to Save, adds a task and completes it. Real planner persistence/reopening tests also remain passing. Tests were corrected to scroll/build the lazy form before asserting the offscreen Save button; failed preliminary candidates are not delivered.

[Patch CI](https://github.com/sillytira/onestep-ios/actions/runs/44125129904):42 regression tests and analysis pass. Windows x64 release builds and its executable stays running during the hidden launch check. [Final Android CI](https://github.com/sillytira/onestep-ios/actions/runs/44127642483) also passes42 tests and builds the release APK, then launches it on API35, opens More/reminder settings and posts native notification2147483646 without exact-alarm permission. No invalid_icon/FATAL appears. The harness recovers only the exact emulator Pixel Launcher ANR; it does not dismiss OneStep errors. Android packaging/smoke source:d9d07c4346882c2ad4907f7922b5defea8d9018c; Windows functional source remains84e257086f797e200e8afff749ff7258e33132d4.

The Android patch retains meow.tira.onestep and the permanent signing certificate; official signature and unchanged CI application-payload checks are recorded in PACKAGE-VERIFICATION.json. Windows remains OneStep / Tira-OneStep.exe, version0.10.1, with required runtime DLLs/data. Artifact and package digests, source/private-key scans and bundle checksums are verified. Private signing/enrollment material is not included.

Core UI previews use a synthetic widget planner. *-device.png files are actual release-APK emulator captures. They are not physical-phone acceptance. Windows launch plus shared desktop UI tests do not establish every installed Windows interaction. Check retained data after installing over the same app identity.

## Live backend activation

After fresh explicit approval, tested006/007 were deployed together as one transaction through the authenticated main Supabase project's Edge SQL Editor. Live read-only owner-context queries verify owner recognition, economy6,1point/minute,1,000/day limits, beta-v1 and initial encrypted sync availability. RLS is enabled; anonymous RPCs/tables are denied; private implementation execution is denied; no moderator grants were created and the existing owner remains. Public-client HTTP checks return401/42501 for the new private endpoints; Auth settings returns200. See SERVICE-STATUS.md and live-service-http-verification.json.

No real login password/session/privileged key was read or published. No real awards, artificial users, grants or planner snapshots were written for verification. Production tests were limited to read-only contracts/access checks after the approved migration. Actual signed-in phone XP awards, two-device encrypted merge, moderation revocation/family and Apple Screen Time acceptance remain for installed users. The previous0.10 bundle remains unchanged and its pending-deployment notes describe the earlier state.

Signed APK SHA256:6bc96903a9f0abbb12d78784f577c939dd951e7fdc66092d6f920a1357267f7c. CertificateSHA256:ad35a758e1304c98d1574b7849d25e2d040379bd7a1cfc391a2349f2436bf312. All96 non-signature application members match the tested CI APK. The existing signing identity is retained.
