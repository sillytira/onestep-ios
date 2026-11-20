# OneStep 0.10.2 — account reconnection

This update fixes client session handling on Android, Windows and iPhone. Empty refresh tokens are rejected before sending a request, incomplete login responses cannot replace the saved account, concurrent refreshes share one rotation, and delayed responses cannot overwrite a newer session. Permanent credential rejection presents Reconnect instead of endlessly retrying. Temporary network/503 failures remain retryable.

## Recover your existing account

1. Update over your existing app. Preserve a backup; do not uninstall or delete app data.
2. Open Bank → Account → Reconnect this account.
3. Enter the existing account password on your device and reconnect. Never send your password to Codex.
4. Refresh Bank, then retry XP/points or opt-in private sync. Pending completions remain saved and use their existing receipt IDs.

A missing/revoked refresh token requires password authentication once. The server cannot safely recreate that credential without authenticating you. Your saved identity, family link, parent offline code, local planner and pending XP are retained. Reconnecting cannot switch a saved child to another account; parent-authorized device sign-out remains required.

## Packages

- Android: install OneStep-0.10.2-beta-17.apk over the matching app; the permanent signing certificate is unchanged.
- Windows: close OneStep, extract the entire Windows ZIP and run Tira-OneStep.exe with its DLLs/data beside it.
- iPhone: sign the matching 0.10.2 IPA under the same app identity and install as an update. Choose the Screen Time variant only with the required Apple-approved entitlements/provisioning. The old-identity bridge is for users still on tech.sillycat.onestep; do not switch identities casually.

## Service and acceptance limits

Migrations 001–007 remain deployed; do not reapply 006/007. Auth settings are reachable and anonymous access to private account functions is correctly denied. No new database permissions, accounts or rewards were created for this fix.

Automated fixtures use synthetic credentials. Installed-account password recovery, locked-phone reminders, retained device data and two-device sync still need checking on your actual devices. These packages do not automatically restore a lost refresh token or prove real-account recovery. Optional standalone Bank/Kids/Parent companion binaries are not included in this main-client patch.
