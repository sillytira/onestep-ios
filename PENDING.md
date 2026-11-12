# Remaining acceptance checks

Version 0.7 retains personal rewards, bounded weekly rankings, server-side app-time receipts, the native Apple shield/unlock lifecycle, and an opt-in private next-action widget. The 0.7 repair adds account/navigation/UI corrections with 62 passing app tests. Main-instance migration 005 remains deployed; no new database migration is needed. Build evidence is recorded separately; these outcomes still need real users/devices:

- **Family acceptance:** owner account exists in Auth Users; confirm owner/admin GUI, separate parent-child linking, one approval credit, hidden child identity, and a previously synced offline parent code. No owner password was read or entered by Codex.
- **Signed iPhone acceptance:** update over the same signing identity, verify retained history, locked offline alerts, Live Activities, next-day behavior, and real phone-to-PC transfer.
- **Apple Screen Time provisioning:** use the special variant with appropriate Family Controls/App Group profiles and Apple individual/family authorization. Test blocking, 15/30/60-minute point-funded unlocks, recovery after lost responses, expiry while closed/locked, reboot/timezone changes, and child settings/PIN gates. Compilation does not prove signing capability or OS behavior. Individual authorization remains revocable by the user. A VPS does not supply Apple entitlements.
- **Private widget:** opt in only on a provisioned variant, verify disabled/hidden titles by default, selected next action, stale-day fallback, and lock-screen privacy.
- **Time Sensitive:** validate signing/system access; ordinary notifications are the fallback. No Critical Alerts.
- **Android continuity:** final releases reuse the saved private signing certificate. Verify installing 0.7 over delivered 0.6 retains data. Raw CI test-signed APKs need local release signing unless private CI secrets are configured.

Continuous online planner merging, advanced folders/repeat rules, custom encrypted planner storage, and password-encrypted exports remain separate future work. Native code updates and Apple profile renewal still require signed app installation; content updates cannot bypass either requirement.
