# OneStep 0.7 — repair verification

This release follows the user's report that the 0.6 apps broadly failed in use. It fixes identifiable account/navigation/UI defects; it does not treat successful packaging as proof that every physical-device feature works.

## Delivered builds

Twelve packages: native main, old-ID bridge, and Screen Time IPAs version0.7.0 build23; main Android, Windows EXE bundle, Linux AppImage; six Bank/Kids/Parent phone companions version0.7.0 build12. IPAs remain unsigned. Android release certificates match delivered0.5/0.6.

## Concrete repairs

- Bank now has Home, Activity, Rankings, and Account destinations, clear sign-in/join modes, balance-first typography, original gradient virtual-points cards and real ledger activity. Native Bank is a main tab; More retains Notes/History/settings. Desktop has adaptive expanded/compact navigation and direct task/Bank actions.
- One shared account client per process coalesces refresh-token rotation. Requests reject responses after switching accounts, and personal reward outbox registration/claims stay bound to the original principal. Obsolete manual connection values no longer override the main service. Same-account reconnection preserves family links. Native account vault reads run outside the UI thread. Optional rankings/policy failures do not hide the core account snapshot.
- Personal statement queries filter by current user instead of relying on parent-visible RLS rows. Parent policy edits survive polling until saved. Editing a task without an available account preserves its existing reward binding. Empty task names show feedback.
- Apple Screen Time exposes actual authorization/selection state, a clear unsupported-profile screen, website-category shields, and parent settings expiry when leaving the foreground. Shared shield state is written before stopping monitoring. App-level URL routes survive startup and reject unrelated URLs.

See UI-REPAIR.md for the full list and official Apple/Microsoft/Revolut references used. There are no new database permissions or migrations in this release; deployed001–005 remain unchanged.

## Test evidence

- [Native tests and three IPAs](https://github.com/sillytira/onestep-ios/actions/runs/43237404155): **27 core +12 native simulator tests**, all three device builds passed. New coverage checks route parsing and retaining an incoming destination until the interface consumes it.
- [Portable tests/builds](https://github.com/sillytira/onestep-ios/actions/runs/43237655845): **23 tests**, static analysis, Windows launch, Linux render/launch, Android packaging and Bank design capture passed.
- [Six companions](https://github.com/sillytira/onestep-ios/actions/runs/43237655932): verification and all role/platform builds passed.
- [Icon-correct Bank preview](https://github.com/sillytira/onestep-ios/actions/runs/43233951904): rendered the actual BankOverview component with clearly labeled synthetic data and loaded Material icons.
- Existing [SQL tests](https://github.com/sillytira/onestep-ios/actions/runs/43219591679) cover unchanged server authorization, child privacy, caps, idempotency, and app-time policies.

Total **62 app tests**, plus the unchanged SQL suite and separate visual capture. New portable tests cover large text at320/1080 widths, cached account navigation during a simulated outage, eight concurrent requests rotating a session once against an actual loopback HTTP fixture, old configuration migration, desktop create/complete controls, and separate real disk save/complete/reopen persistence. A loopback fixture also rejects obsolete responses after an account switch. Guest sign-in hides beta-registration fields until explicitly selected.

## Package inspection

Artifact digests and original CI checksums are verified before signing. Independent parsing verifies IDs,0.7 versions/builds, arm64 IPAs, extension counts/identities, Android ABIs, Windows PE x64/name, and Linux x86-64 type2. Ordinary/bridge IPAs have one extension; Screen Time has two; companions have none. Final APKs verify with official apksigner v2/v3 and certificate SHA256 ad35a758e1304c98d1574b7849d25e2d040379bd7a1cfc391a2349f2436bf312. All95 non-signature APK members per package match tested CI payloads. Owner invitations, private signing files/passwords and privileged keys are excluded from inspected source/packages; only approved public connection defaults ship.

Functional native source:2e5e999063b1db000fe3fc35da38a6e8d88a80b6. Functional portable/companion source:42c6c3a2fee250a9c9fc5329d3784603956bbd7e. Later source retains CI formatting, documentation and simulator-only preview setup; those preview flags do not alter physical-device code.

## Visual and device limits

The native Now screen, native Bank welcome/sign-in screen, and real Linux desktop screen were visually inspected. The [native Bank layout capture](https://github.com/sillytira/onestep-ios/actions/runs/43235113254) uses a simulator-only direct destination flag compiled out of physical-device builds. The Bank design preview uses sample data, not a real signed-in account. An initial external-link capture showed an iOS Open confirmation; it was not proof of a route failure. External-link confirmation/cold-start behavior remains a signed-device acceptance check. The deterministic native Bank preview opens the destination directly for layout review.

Windows cloud smoke tests pass. A local restricted-runner launch exited; the same binary stayed running when launched outside that restriction. The Windows computer-use inspector exposed no targetable window, so manual Windows clicking is not claimed; control-flow tests and the shared desktop renderer provide the current UI evidence.

Real email/password login across the user's devices, child/guardian setup, physical locked offline alerts, Live Activities, LAN transfer, update retention and actual shield/unlock expiry still require installed-device acceptance. Family Controls/App Group signing and Apple's authorization cannot be supplied by UI code or an ordinary free profile. No Critical Alerts, arbitrary native hot updates or profile-expiry bypass is promised. Follow ACCEPTANCE.md and SCREEN-TIME.md.
