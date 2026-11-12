# OneStep family beta — 0.7

OneStep remains an offline planner. Optional online services add family tasks, parent-approved virtual points, transactions, rankings, and administration. A managed Supabase backend is sufficient; no home server or VPS is required. No points can be purchased with real money. Version 0.6 adds bounded personal rewards and point-funded app time in the separately provisioned native Apple build. See REWARDS.md and SCREEN-TIME.md.

## Choose the apps you need

- OneStep: private planner and a built-in Bank/rewards/account section.
- OneStep Bank: optional standalone balance, transactions, profile, and rankings, using the same service and account as the built-in section.
- OneStep Kids: family-assigned tasks, submission for parent approval, and a points wallet. A Kids account displays its email; it cannot claim a public handle or appear in rankings.
- OneStep Parent: family invitations, task assignment/review, and parent authorization-code management.

Identifiers are meow.tira.onestep, meow.tira.onestep.bank, meow.tira.onestep.kids, and meow.tira.onestep.parent. The native main iOS app retains its Live Activity extension; companions have no extensions. Free Apple signing/app limits still apply, so install only the roles needed on each device. A family uses separate parent and child accounts; installing the Parent app does not grant parent authority to an existing Kids account.

## First connection and owner account

The approved public project URL and publishable client key are built in. Open the account screen and sign in; no manual connection setup is needed. Public client keys identify the application and do not grant user/admin access. Authentication sessions are stored in Keychain/secure storage. Never enter a database password, service-role key, or secret key into a client. Private setup/enrollment files must stay outside the source tree and source archives.

The site owner gets one private, single-use enrollment key bound to the configured owner email. Create the app account once with that email, the enrollment key, and a password you choose. The owner username/handle starts as **meow**; **tira** is reserved and unused. On other clients, use the same app email/password; the enrollment key is not reusable. The Supabase dashboard account is separate from the app account. Email confirmation is disabled for this beta; the invitation proves authorization to enroll, not ownership of an email inbox.

The server consumes a hashed invitation during Auth user insertion, strips enrollment secrets and privilege-like fields from editable metadata, and installs the server-controlled account kind/owner grant. Direct signup APIs cannot bypass this by removing a UI field. Owner/admin privileges are never inferred from an unverified email address or client role. Owner enrollment must be completed by the user; automated tests use synthetic accounts only.

The **Application admin** interface appears in any client after a server-authorized owner/admin signs in. It can list accounts and point balances, generate normal/parent/Kids beta invitations, and record bounded point adjustments with reasons. Every adjustment has an actor and idempotent event ID. It does not reveal database credentials or expose raw SQL execution, schema destruction, or Supabase organization billing. Database-level administration remains in the authenticated Supabase dashboard.

## Invite a family and earn points

1. Owner generates email-bound Parent and Kids beta keys in Application admin. A key is single use and expires after seven days. Do not send codes through public posts or source control.
2. Parent and child create their separate app accounts with those keys. A Kids account has no username field; the email is its display identity.
3. Parent creates a family in OneStep Parent, generates a private 10-minute family invitation, and shares it with the child. This is distinct from a beta enrollment key.
4. Child signs in to OneStep Kids and joins using that family invitation. A linked child cannot join another family unless the existing parent unlinks it first.
5. Parent assigns a small task with a fixed reward of 1–1000 points. Child taps **Ask for approval** when finished. Parent approves or returns it for another try. Points are awarded exactly once on approval, even if the request is repeated.

Only linked family members can see relevant family tasks. Private tasks/routines/notes from the offline planner are not automatically uploaded or converted into awards. The user chooses what becomes a shared family task. These account invitations do not prove age or legal guardianship and do not authorize Apple Family Controls.

## Parent codes and outages

In OneStep Parent, select the child and generate an offline parent code. The app generates ten random digits, stores them securely on that parent device, and uploads only a salted PBKDF2-SHA256 verifier (120,000 iterations). Open Kids online and refresh once so its verifier is cached before relying on offline access. The parent can display the saved code offline later. Another parent device needs setup; plaintext parent codes are not exposed by the child API or embedded in source.

Ordinary child device logout is replaced by **Parent-authorized device sign-out** in every client. A cached correct code can authorize this without the backend. Failed guesses are persisted and locked after five attempts for fifteen minutes; clock rollback is rejected. Device sign-out does not unlink the server family. Only the linked parent can call the unlink operation. Points/history are retained when the link is marked inactive. An unconfigured child device cannot invent its own offline code.

Code rotation/revocation reaches the child at its next successful refresh. The outage path uses the last cached verifier; it cannot receive new server policy while disconnected. This is an application-level guard: it cannot stop uninstalling, clearing app data, resetting a device, using a modified client, or a compromised OS. Version 0.6 supplies a separately provisioned native Apple Screen Time build; see SCREEN-TIME.md for Apple authorization, signing, and real-device acceptance requirements. Android OS blocking is not implemented.

Balances and task snapshots are securely cached per account and labeled with their last sync time. No saved balance displays as unknown rather than zero. New invitations, account creation, task submissions/approvals, public-profile changes, and point adjustments require the backend. Failed online actions are not silently credited or queued as trusted awards. Portable clients refresh while open about every twenty seconds; native Bank has an explicit refresh control.

## Public identities and privacy

Kids cannot opt in to rankings, even with a modified request. Normal users and parents may choose a display name and handle and opt in; rankings show those fields and points, not private tasks or emails. meow and tira are reserved to the owner. Enrollment emails and child profiles remain private to authorized account/family/admin views.

The main private planner continues offline without accounts. Online rewards/account data is a separate store. Signing out does not delete private planner data. Importing a planner backup/local profile cannot grant online roles, create points, or authenticate an account.

## Backend setup from source

Apply backend migrations 001 through 005 to a new empty Supabase project in order. The main instance has received them after approval; do not blindly rerun non-idempotent migrations. RLS is enabled, anonymous table access is denied, and authenticated users have only explicit privileges. Create any initial owner invitation privately using a hashed secret and email binding; never commit that secret or privileged credentials. The existing owner account is present; do not reseed its consumed invitation. Configure email-confirmation policy only after invite gating is installed and tested.

CI database tests cover family isolation, no self-approval, exactly-once credit, beta gate bypass rejection, owner/name binding, metadata privilege rejection, private child identities, and parent-only unlink/PIN setup. scripts/check-public-source.mjs scans source for embedded project keys, JWTs, and private keys. Device enrollment, signed installs, physical offline PIN behavior, and real app notification delivery still need acceptance checks.
