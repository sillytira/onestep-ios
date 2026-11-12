# Optional hosted identity and points foundation

Supabase provides the managed database, Auth API, and admin dashboard; no VM is required. Its Free plan has quotas and may pause after inactivity. The mobile/desktop apps operate without this service. No project is deployed merely by checking out source.

The 0.5 clients connect to the configured main service with an approved publishable key. Password sign-in and single-use beta enrollment, family tasks, parent-approved points, private child identities, and app administration are implemented. Planner sync and OS app-time spending are separate future work; see FAMILY.md and UPDATES.md.

`001_points_foundation.sql` prepares an opt-in top-100 total-points view and an append-only adjustment ledger. Clients may read their own ledger and edit only their own public profile/opt-in. They cannot directly insert/update/delete ledger rows or grant themselves admin. The adjustment function checks a server-side allowlist, validates bounds, locks per account, rejects overdrafts, records the actor/reason, and uses an idempotent event UUID. No user task contents are included. This is a foundation, not a complete rewards product, parental authorization system, or anti-cheat implementation.

Only the project owner should bootstrap an administrator, in the authenticated Supabase SQL Editor, using an actual verified Auth user UUID. Never put a service-role/secret key into a client. Do not grant admin access using a UUID imported from a local profile. Local profiles are untrusted data. The dashboard already lets the owner inspect users and ledger events; a separate real-time admin UI is future work. Task awards and app-time redemption require further server-side authorization rules and authenticated sessions before activation.

Changing a displayed balance should always add an audited adjustment, not overwrite or erase past entries. Public rankings are opt-in and omit email, task text, app usage, private reasons, and IDs. Migrations 002–004 add application family links and private child identities. These invitation links do not establish verified age or legal guardianship.

No real-money purchasing or monetary value is supported. The optional Bank, Kids, and Parent phone clients are built and share the managed service. Screen Time enforcement is local Apple platform work and depends on Family Controls authorization, managed entitlements, and suitable signing; database hosting does not unlock those capabilities.

Apply migrations only to a new empty OneStep project after reviewing them. They are not written to overwrite an existing application's schema. The CI database test uses synthetic users and no real account data.
