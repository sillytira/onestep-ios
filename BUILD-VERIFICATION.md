# OneStep 0.8 - economy and XP verification

## Implementation and activation status

The clients implement a fixed one-point/minute Screen Time economy, 1,000 daily task-earned points and redeemed minutes, and a separate non-spendable XP ledger with independent opt-in weekly rankings. The native app guards redemption behind the new service contract. Detailed rules, offline behavior and exclusions are in ECONOMY.md.

**Main-instance migration 006 is not deployed.** This CLI has no available Edge browser host/native pipe and no privileged Supabase connection. Migrations 001-005 remain the live baseline. Public source upload, successful builds and synthetic SQL tests do not activate the live service. The owner must apply only backend/006_economy_xp.sql to the existing project through its authenticated SQL Editor, or resume with accessible Edge. No privileged key, owner invitation or signing secret is published.

## Evidence

- [PostgreSQL 16 upgrade and authorization suite](https://github.com/sillytira/onestep-ios/actions/runs/43302472191): passed all 001-005 tests followed by 006. Covers 1,000-point earning/leaderboard ceiling, one point per minute, one-minute redemption, repeated receipts, a 999-minute purchase, account-wide daily spending across devices, fixed child prices/lower allowances, parent reward limits, independent XP cap/spacing/replay, independent public opt-in, child exclusion, RLS and anonymous/direct-write denial. Synthetic users only; never run test SQL on production.
- [Portable verification and Android/Windows/Linux builds](https://github.com/sillytira/onestep-ios/actions/runs/43298783939): 25 tests and static analysis passed; all three packages built. New XP tests cover account binding, undo/re-complete uniqueness, backup round-trip, guest behavior and skipped routines.
- [Six Bank/Kids/Parent companions](https://github.com/sillytira/onestep-ios/actions/runs/43298783753): verification and all role/platform builds passed.
- [Final native tests and three IPA variants](https://github.com/sillytira/onestep-ios/actions/runs/43301108444): 29 core tests, 12 native simulator tests and all three physical-device builds passed. The earlier run passed 29 core and 12 native simulator tests and built normal/bridge apps, then exposed an extension source dependency. XP types were moved to their own file so the DeviceActivity monitor retains only shield rules. No failed-build IPA is delivered.

Passed app-test total: 29 core + 12 native simulator + 25 portable = 66, plus the SQL suite. This is not physical-device acceptance.

Functional portable/companion source: 1a4e5070bfd9cb06a3eea03eae299370c99e03b9. Final migration and parent-approved family-task XP source: c9a898907a846791cd0bcbbc2f77cbf31378853e. Native target-dependency repair: 85ccb22f837003680ec3fc362bc2c992ee00d498. Final source retains CI Dart formatting and updated documentation without changing tested app behavior.

## Package and device boundaries

The release process verifies outer GitHub artifact digests and inner package checksums before assembly; signs Android packages with the saved permanent private key; compares certificates to delivered 0.7 and compares non-signature payloads to CI artifacts. Package parsing checks identities, 0.8 versions/builds, CPU architecture and extension counts. Source archives include hidden workflows and exclude private files and known secret material. See the final JSON reports and SHA256SUMS.txt in the delivered bundle for the completed inspection results.

Main identifiers remain meow.tira.onestep and the existing companion suffixes. Native build 25 contains one Live Activity extension in normal/bridge variants, and adds a DeviceActivity monitor in the separately provisioned Screen Time variant. Portable/companions are 0.8.0+13. IPAs are unsigned. The same Apple signing identity and appropriate Family Controls/App Group profiles remain necessary; an ordinary free profile is not promised to provide them.

Apple authorization and system expiry behavior require a real signed iPhone. The XP and points services require live migration/account acceptance. Locked offline reminders, Live Activities, guardian/individual authorization, actual shields/expiry, transfers and update retention remain in ACCEPTANCE.md/PENDING.md. Windows has cloud launch/control-flow evidence; no new manual Windows click-through is claimed. Bank component design previews use explicitly synthetic data and do not establish a real signed-in XP session. The user clarified that their earlier Screen Time issue came from incorrect signing.
