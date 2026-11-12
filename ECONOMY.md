# Points and XP - 0.8 beta

Migration `backend/006_economy_xp.sql` upgrades an existing OneStep project that already has 001-005. **It is staged and tested, but has not been deployed to the main instance from this CLI session.** Edge's browser host is unavailable here. Do not replay the old migrations or run the synthetic test scripts on the live project.

## Spendable points

- One point buys one minute of a native Apple Screen Time unlock. Choose 1-1,000 minutes, with 15/30/60-minute shortcuts.
- Earn up to 1,000 task points per UTC day; redeem up to 1,000 minutes per UTC day across all devices. A balance can carry over and exceed 1,000; the limits apply to each day's activity, not the saved balance.
- Personal task rewards remain 0-100 each, with at most 20 counted tasks/day and the existing duplicate-title, age and rate filters. Weekly earned-point rankings inherit the new 1,000/day ceiling. Spending and admin adjustments do not count as earned points or leaderboard credit.
- Parent-approved family task awards share the daily earning ceiling. An approval that would exceed it remains submitted, with an error explaining that it can be approved later; its promised reward is not silently reduced. Family awards remain outside personal-task rankings.
- A parent can disable child redemption or keep a lower daily minute allowance. The exchange rate is fixed at one for everyone. Existing child minute limits are preserved; existing prices are migrated to one. Old purchase receipts remain unchanged and recoverable.
- Purchases lock the account transaction, check balance and allowance, and use an idempotent receipt. Repeating a request cannot charge twice. A lost reply can be recovered through the same receipt.

Bank > App time on native iOS opens the existing FamilyControls/ManagedSettings/DeviceActivity flow. The service confirms the purchase before the app removes its selected shields. Expiry is monitored locally. Apple authorization, appropriate Family Controls/App Group profiles, and installed-device checks are still required. The ordinary IPA and Flutter companions cannot obtain those entitlements from the server. See SCREEN-TIME.md.

The updated native redemption screen requires economy status version 6 and stays disabled if migration 006 is missing, unreachable, or returns a different contract. It does not quote 1,000-minute availability against the old service. New purchases require a connection; the planner and existing OS-managed expiry remain local.

## Non-spendable XP

Complete a task or daily routine step while signed into an app account to queue 10 XP, whether or not the task has a spendable point reward. Skipping, snoozing, opening the app, and checking microsteps do not create awards. Existing completion history is not backfilled. The initial cap is 1,000 XP per UTC day, independent of the points cap.

Parent approval also grants the child 10 XP for the approved family task, once and within the independent XP cap. Approval remains required for the spendable family reward. Merely submitting a family task does not award it. Parent/Kids companions show the resulting account total.

XP events are saved atomically with planner completion, bound to the signed-in account, and included in backups/LAN snapshots. They contain completion IDs and kind, not task titles. A task ID or routine ID/day can award once per account; undo/re-complete, retrying and importing the same queue do not multiply XP. Cross-platform event keys match. The service enforces fixed awards, a five-second claim interval, daily caps, and unique account/event keys. Claims retry while the main planner is open. Server credit day is the UTC day a queued claim is accepted, including after offline use. The total shown in Bank is the last server-confirmed account total; it is not a provisional local award.

The XP leaderboard is a separate weekly top-100 query and ledger, selected with XP in Rankings. Membership is independently opt-in and defaults off, even for a points-ranking member. Save XP visibility from Account/Public profile. Children and linked child identities are excluded from both public ranking systems. A child's own XP remains private. XP cannot fund app time, be adjusted using the points admin form, or become a cash balance. Weekly rankings start Monday 00:00 UTC; the XP account total persists.

Both planner-based systems are self-reported and bounded; these filters do not prove that a human actually did a task.

## Activate the live upgrade

The project owner must run **only** `006_economy_xp.sql` once in the authenticated Supabase SQL Editor after reviewing the tested migration. It changes no account roles or admin ownership. It adds a private XP table/read policy, an independent profile visibility flag and authenticated RPCs. Anonymous access and direct XP writes remain denied. Existing authenticated RPC grants are retained for replaced point/policy functions.

Before applying, take the normal database backup/snapshot. After applying, use a real account in the updated app: refresh Bank, complete a new task and routine, confirm XP is separate from points, opt in to XP rankings, redeem one point for one minute, and test expiry on the properly signed device. Test parent approval at the cap and a lower child allowance. Public client URL/key remain built in; no database password or privileged service key belongs in a client or public source.
