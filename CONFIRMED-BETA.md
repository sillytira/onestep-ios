Current service update: migrations001–007 are live after explicit approval. See [SERVICE-STATUS.md](SERVICE-STATUS.md). Android/Windows0.10.1 removes the duplicate top Save; native0.10/build33 is unchanged. Older pending-deployment statements below describe the earlier release state.

# OneStep 0.10 Beta — confirmed updates

Main Android 0.10.0-beta build 15 and native iPhone 0.10.0 build 33. Install over the same app identity with the same signing settings after making a verified backup. Keep the old app until you have checked your saved tasks. Windows/Linux and optional companion binaries remain the previous release.

## What changed

- More → Planner shows day, week and month views, dated tasks including completed work, unscheduled tasks and daily routine records. It opens the existing task editor. It does not create speculative future tasks or catch-up alerts.
- Repeating tasks support intervals, selected weekdays, and monthly days. A monthly 31st clamps in February and returns to the 31st afterward. Completing late creates one next occurrence after the current time. Daily routines retain their separate daily history.
- Android task rewards are visible in the editor even before sign-in. Signed-out values are local drafts; sign in and save explicitly to enroll a task. Ordinary/parent rewards are 0–100 points per task, with server filters and the 1,000-point daily cap after migration 006. Children still need parent approval. A task badge is not a confirmed award.
- iPhone More now includes Planner, XP Beta, Notes, History, routine updates, backups/Wi-Fi, encrypted sync, family/accounts, Screen Time, reminders and language settings. Points and XP rankings are separate. Beta ranking cohorts stay separate from future production earnings; private lifetime XP is retained. Children remain excluded.
- English plus German, Ukrainian, Russian, Polish and Bulgarian core navigation/planner/settings copy. There are 131 translated core messages per requested language. Detailed service/admin explanations still fall back to English in this beta. Task titles and notes are never sent to a translation provider.

## Encrypted backups and recovery

Export with a passphrase of at least 12 characters. Exports use PBKDF2-HMAC-SHA256 (600,000 rounds, random 16-byte salt) and AES-256-GCM (random 12-byte nonce, authenticated format/version). Apple and Android use the same format; a shared independent test vector verifies interoperability. Wrong passwords and tampering fail before any replacement. Clear planner content is limited to 8 MiB; encrypted files to 12 MiB.

Save the passphrase separately in your password manager. There is no password-reset or server recovery for encrypted files. Try importing a copy before relying on it. The old readable JSON format is accepted for migration. Import remains a previewed replacement with local recovery; it is not an automatic merge. Wi-Fi transfer retains its existing encrypted, foreground snapshot protocol.

This encrypts exported files and cloud planner snapshots. Local planner/recovery files continue to use the existing platform/file protection and are not a new encrypted database. Account sessions, PIN verifiers and sync passphrases use device secure storage and are not included in planner exports.

## Optional encrypted cloud sync

Requires an account and migration 007. On every device, back up first, check the local planner, then enable More → Private planner sync with the same passphrase. The server stores the encrypted envelope and a revision number, never the passphrase. There is one cloud planner per account. Enabling another account does not automatically upload the device-wide local planner.

Sync checks about every 30 seconds while open and on resume. Mobile systems do not guarantee background sync. Independent record edits merge using the last synchronized base; conflicting edits or edit/deletion require an explicit device/cloud choice. Server compare-and-swap rejects stale revisions. New local edits arriving during upload survive and synchronize on the next pass. Timers remain on their original device. Pause retains the encrypted cloud copy. Losing the passphrase can make that copy unrecoverable; keep a tested backup.

## Owner-controlled moderation

Bank → Account → Service administration reads server-assigned permissions. Only the enrolled owner can grant/revoke `accounts.read`, `accounts.ban`, `points.adjust`, and `invites.issue`. No moderators are assigned by migration 007. A moderator cannot grant rights or suspend the owner. Ordinary moderators do not receive child/email account lists. Audits are owner-only.

Suspension blocks OneStep online data/API access; it does not disable Supabase Auth sign-in, erase offline data, or revoke Apple authorization. Point adjustments are audited and retry-idempotent, cannot produce negative balances, and never inflate earned-points rankings. Invitations cannot create another owner. The console does not expose database passwords, secret keys, billing or arbitrary SQL.

## Live service setup — pending

Last known live state is migrations 001–005. The owner chose to restore Edge access later, so neither 006 nor 007 was deployed during this update. Local offline changes work; online XP/new economy, encrypted cloud sync and moderation require the service upgrade. Clients report errors/setup needs instead of claiming success.

In the authenticated main Supabase project's SQL Editor:

1. Check which migrations are already applied. Back up the database using your usual process.
2. Run `backend/006_economy_xp.sql` only if missing.
3. Run `backend/007_sync_moderation_beta.sql` only if missing. It adds private sync/moderator/audit tables, restrictive access rules and guarded RPCs; it preserves existing owner/account records.
4. Reconnect clients and verify owner permission status, own XP, no child rankings, and same-account encrypted sync between two devices. Test moderator grants using a separate adult test account; revoke them afterward.

Never run `*test.sql` files against the live service. They create synthetic users/fixtures and are only for isolated CI databases. No service-role/database secret belongs in a client or public repository. The approved public connection URL/publishable key remains built in.

## Verification and remaining checks

Database tests use synthetic users on isolated PostgreSQL: authorization, revocation, suspension/old-RPC/direct-table denial, CAS, account isolation, audited/idempotent adjustments, child privacy and beta/production cohort separation. Native tests verify recurrence, persistence and cross-platform encrypted exports; portable tests exercise merging, network-race retention and translations. See BUILD-VERIFICATION.md in the delivered bundle for exact build evidence.

The owner confirmed basic tasks, reminders, routines and updating work. New signed-device checks remain: advanced repeats across timezone/DST changes, encrypted file exchange both directions, conflict resolution on two real accounts/devices, family/moderation use after service deployment, and signed Screen Time/widget/Live Activity behavior. Free Apple signing cannot supply unsupported entitlements. Follow SCREEN-TIME-SIGNING.md for the special IPA. In-app content updates still update data, not native code; this feature release needs an APK/IPA update.

Primary references: [SwiftUI](https://developer.apple.com/documentation/swiftui), [CryptoKit AES](https://developer.apple.com/documentation/cryptokit/aes), [Flutter internationalization](https://docs.flutter.dev/ui/internationalization), [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [OWASP password hashing guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).
