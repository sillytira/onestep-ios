# OneStep 0.6 — release verification

Verified November 12, 2026. Native iPhone 0.6.0 build 17; portable/companion 0.6.0 build 11. Twelve packages: ordinary main IPA, old-ID bridge IPA, optional Screen Time IPA, main APK, Windows ZIP/Tira-OneStep.exe, Linux AppImage, and Bank/Kids/Parent IPA+APK pairs. IPAs are unsigned and require suitable signing.

## Implementation

Personal enrollment chooses 0–100 points and binds to the signed-in account. Offline Done is immediate; service awards retry while open. Migration 005 enforces server age/spacing, normalized duplicate titles, daily 20-task/500-earned-point caps, and exactly-once credit. Weekly opt-in top-100 rankings offer task count or earned points, excluding children, admin grants, and spending. Self-reports remain self-reports, not proof of effort.

Native Screen Time uses Apple's FamilyControls authorization/picker, ManagedSettings shields, and DeviceActivityMonitor extension. Individual mode is user-revocable; child settings are parent-code gated and require Apple's family authorization. Point purchases show policy/cost, reject changed prices before debit, persist receipt IDs, and clear shields only after confirmation and an armed monitor. Parents load saved policies and keep child selection consistent across task/policy/PIN panels. An opt-in private App Group widget has titles hidden by default and stale-day checks. Ordinary and capability-dependent IPAs remain separate.

## Tests and builds

- [Native tests and three IPAs](https://github.com/sillytira/onestep-ios/actions/runs/43219591626): 25 core +11 native simulator tests passed, all three device variants built with Xcode 26.6. Reward-binding transfer and pure lease-expiry tests supplement persistence/Live Activity tests.
- [Portable tests and packages](https://github.com/sillytira/onestep-ios/actions/runs/43222123539): 14 tests, static analysis, Android/Windows/Linux builds and desktop launch checks.
- [Six phone companions](https://github.com/sillytira/onestep-ios/actions/runs/43222123422): Bank/Kids/Parent iOS and Android with verification before packaging.
- [SQL authorization tests](https://github.com/sillytira/onestep-ios/actions/runs/43219591679): migrations001–005 with synthetic users; age/duplicate filters, caps, child denials/private reads, denied direct writes, parent prices, changed-quote rejection without debit, and idempotent purchases.

Total: **50 app tests**, plus SQL tests. Native/backend source: [80f4522](https://github.com/sillytira/onestep-ios/commit/80f452200a4661b2e5f8d1f5a345fc25c2b48a2a). Portable/companion selector correction: [b0b425b](https://github.com/sillytira/onestep-ios/commit/b0b425b5a6bb8083ca3831549596385576ecaab8). Later source retains CI formatting/lock and documentation.

Migration005 was explicitly approved and deployed to the main instance through Edge, returning success. Live catalog inspection confirmed all three new tables have RLS enabled, anon SELECT denied, authenticated direct INSERT denied. Verification did not change real balances. An owner account was visibly present; no owner password was read/entered by Codex.

## Packages, signatures, and privacy

Artifact ZIP digests and original package manifests are checked before signing. Independent inspection verifies IDs, versions/builds, native arm64, Android ABIs, Windows x64 PE/name, Linux x86-64 type-2 AppImage, and extensions. Ordinary/bridge each have one extension; Screen Time has two and its enabling Info flag; companions have none.

All four final APKs use the existing private RSA-3072 release key and verify with official apksigner v2/v3. Certificate SHA256 ad35a758e1304c98d1574b7849d25e2d040379bd7a1cfc391a2349f2436bf312 matches delivered0.5. Non-signature APK members match tested CI payloads. Final SHA256SUMS describes release-signed files. Keystore/password remain outside public source and archives.

Source/package scans exclude owner invitation plaintext, private signing material, privileged keys, and session JWTs. Only the user-approved main-instance publishable client configuration ships publicly. Source ZIP includes reproducible workflows and excludes private setup/signing files.

## Device boundaries

Unsigned compilation does not establish Family Controls provisioning, signed iPhone shield/expiry behavior, locked offline reminders, real phone-to-PC transfer, update retention, or parent-child device acceptance. Use ACCEPTANCE.md. Free Personal Team support for special Apple capabilities is not promised; ordinary planner installation remains available. No Critical Alerts, tamper-proof management, unrestricted SQL admin, executable hot updates, or signing-expiry bypass is claimed. See SCREEN-TIME.md, REWARDS.md, PENDING.md.
