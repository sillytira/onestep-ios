# OneStep 0.10 — remaining prerequisites

The owner approved both Android and Apple, confirmed basic tasks/reminders/routines/updating work, and approved owner-controlled moderation. Calendar, advanced recurrence, encrypted exports/cloud merge, Apple More/XP Beta and five core UI languages are implemented; see CONFIRMED-BETA.md. Live001–005 remain the baseline. Both006 and007 are staged/tested but NOTdeployed; the owner will restore Edge access later after Windows denied automation. Apply only missing migrations in order, never synthetic testSQL. Online feature acceptance follows deployment.

New physical-device acceptance: import encrypted exports Apple→Android and Android→Apple, verify password/tamper recovery, month-end/early completion/timezone recurrence, real two-device conflicting edits/reconnection, service moderator revocation, beta cohort privacy and signed Screen Time/widget/Live Activity behavior. The user-reported basic acceptance does not establish these new scenarios. Prior desktop/companion binaries are unchanged.

Earlier acceptance context:

# Remaining acceptance checks

Version 0.8 adds fixed 1-point/minute redemption, 1,000-point daily earning/spending limits, and separate XP/opt-in rankings. Migration 006 is tested but not deployed: the CLI has no Edge/browser host. Apply only 006 to the existing project; updated clients fail closed for redemption until its contract is available. See ECONOMY.md. It retains the prior account/navigation repairs, native Apple shield/unlock lifecycle and private widget. The 0.8 clients pass 69 app tests plus the backend suite. Main-instance migrations 001–005 remain deployed; migration 006 is pending. Build evidence is recorded separately; these outcomes still need real users/devices:

- **Family acceptance:** owner account exists in Auth Users; confirm owner/admin GUI, separate parent-child linking, one approval credit, hidden child identity, and a previously synced offline parent code. No owner password was read or entered by Codex.
- **Signed iPhone acceptance:** update over the same signing identity, verify retained history, locked offline alerts, Live Activities, next-day behavior, and real phone-to-PC transfer.
- **Apple Screen Time provisioning:** use the special variant with appropriate Family Controls/App Group profiles and Apple individual/family authorization. Test blocking, 15/30/60-minute point-funded unlocks, recovery after lost responses, expiry while closed/locked, reboot/timezone changes, and child settings/PIN gates. Compilation does not prove signing capability or OS behavior. Individual authorization remains revocable by the user. A VPS does not supply Apple entitlements.
- **Private widget:** opt in only on a provisioned variant, verify disabled/hidden titles by default, selected next action, stale-day fallback, and lock-screen privacy.
- **Time Sensitive:** validate signing/system access; ordinary notifications are the fallback. No Critical Alerts.
- **Android continuity:** final releases reuse the saved private signing certificate. Verify installing 0.8 over delivered 0.7 retains data. Raw CI test-signed APKs need local release signing unless private CI secrets are configured.

Calendar, advanced repeats and encrypted exports are now implemented in0.10; online conflict-aware sync requires007. Advanced folders and a custom encrypted local planner database remain separate future work. Native code updates and Apple profile renewal still require signed app installation; content updates cannot bypass either requirement.
