# OneStep online service — live November 17, 2026

Migrations001–007 are now deployed to the existing main Supabase project. After explicit approval, the tested006/007 scripts were applied together as one transaction through the authenticated Edge SQL Editor. Existing owner/account records were retained; no moderator permissions were assigned automatically. Do not apply006/007 again to this project.

The live owner-context read-only checks report economy version6,1point per minute,1,000 earned points/day and1,000 redeemed minutes/day before any lower parent allowance. XP has its own1,000/day limit and independent opt-in leaderboard. Owner access remains recognized, with the beta-v1 ranking cohort. Encrypted planner sync is available; enabling it still requires your account, explicit opt-in and the same saved passphrase on every device.

Live permission audit: private tables have RLS; anonymous sync RPC access is denied; signed-in RPC access is enabled; private implementation functions cannot be called by clients; one existing owner is preserved. No moderator was auto-granted any permission. HTTP checks against the public client API return permission-denied401/42501 for anonymous access to the three new RPCs and the private sync/moderator tables, rather than missing-schema errors. The public Auth service settings endpoint is reachable.

Open the app's Bank/account page and refresh. Sign in normally if your session expired. Pending XP retries while the app is open. More → Private planner sync can now be enabled after a verified backup. Owner moderation is under Bank → Account → Service administration. No new connection URL or manual key entry is required. Existing native0.10/build33 can use the service without a new IPA.

These checks confirm deployment, contracts and access boundaries; they do not claim a real phone completed an XP award, two-device encrypted merge, moderator revocation or Apple app-time redemption. Those remain installed-account/device acceptance checks. No real passwords, session tokens, owner invitation, private keys or privileged service key were read or published. No synthetic test SQL was run against production.

Older release documents saying006/007 are pending describe their state when those archives were produced. The old archives/checksums remain unchanged. This file records the later live deployment.
