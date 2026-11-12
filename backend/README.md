# Hosted OneStep accounts, points and XP

Supabase provides the managed Auth/database service. Offline planner use and local Wi-Fi snapshots do not require a server. Public connection defaults are embedded in the clients; privileged service keys, database credentials, private Android signing material and owner enrollment stay outside public source and archives.

## Main instance status

Migrations 001-005 were deployed with explicit authorization. **006_economy_xp.sql is tested and staged, but not deployed.** The CLI session has no available Edge/browser host or privileged database connection. To activate the 0.8 economy/XP clients on the existing project, the project owner must apply only 006 once in the authenticated SQL Editor. Do not replay 001-005 or any synthetic test script on live data. Review the normal backup/snapshot before applying.

## Migration sequence for a new project

1. 001_points_foundation.sql: private profiles, append-only points ledger, server-controlled administrators and audited adjustments.
2. 002_family_services.sql: invitation-based families, parent-assigned tasks, child submissions and exactly-once parent approval.
3. 003_beta_identity.sql: invite-only enrollment, owner/email binding, reserved handles, server roles and email-only child identity.
4. 004_parent_controls.sql: parent-only unlink and salted offline-code verifier storage.
5. 005_personal_rewards.sql: bounded self-reported task rewards, private child policies, weekly opt-in task/point rankings and idempotent app-time purchases.
6. 006_economy_xp.sql: fixed 1 point/minute, 1,000 daily earned points and redeemed minutes across devices, lower optional child allowances, private XP events/status, independent opt-in XP rankings and authenticated RPCs. Existing receipts stay unchanged; existing child prices become one point/minute and existing minute allowances stay intact.

See ../ECONOMY.md for exact limits, award rules, offline behavior and activation checks. XP and points are separate ledgers; admin point adjustments and spending cannot inflate earned rankings. XP cannot fund Screen Time. Children and linked child identities are excluded from both public rankings, regardless of client flags.

## Authorization and testing

Private tables use row-level security. Clients cannot write points or XP ledger rows directly; functions validate enrolled identities, parent links, bounds, replay and account-wide locking. New XP functions are authenticated-only, and only the user can read their XP events. Independent XP leaderboard membership defaults off. No role or administrator grants are added by 006.

The cloud PostgreSQL 16 workflow runs economy-xp-test.sql, which chains the earlier authorization tests then applies the upgrade using disposable synthetic users. It covers caps, fixed pricing, a one-minute purchase, cross-device spending, receipt replay, child allowances, parent reward ceiling, independent XP, visibility, child privacy and denied anonymous/direct writes. **Never run these test scripts against a live project.**

Planner activity is self-reported; the filters bound spam and do not establish proof of effort. Backend purchases do not grant Apple capabilities. Native blocking still requires Family Controls/App Group provisioning and OS individual/guardian authorization; the companion clients only configure the online family/account service.
