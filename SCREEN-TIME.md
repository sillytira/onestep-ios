# Optional native Apple Screen Time beta

Use the separately named screen-time IPA only with signing profiles supporting Family Controls and App Groups. It keeps `meow.tira.onestep`, its `.liveactivity` extension, and adds `.activitymonitor`. The app/monitor use Family Controls; all three targets share `group.meow.tira.onestep`. The ordinary IPA has one Live Activity extension and keeps the planner usable without these capabilities. Flutter Bank/Kids/Parent companions configure accounts/policies; they do not block iOS apps themselves.

The native integration uses Apple's AuthorizationCenter, FamilyActivityPicker, ManagedSettings shields, and a DeviceActivityMonitor extension. Normal users request individual authorization (revocable in system settings). Child mode requests Apple's family authorization; an app PIN cannot replace guardian authorization or turn an ordinary account into an OS-managed child. Choose apps/categories/websites, apply blocking, then buy a timed unlock with earned points. Opaque Apple selection tokens remain on the device/shared container.

The app verifies the system accepts monitoring before a debit, persists a pending receipt identifier securely, and clears shields only after the service confirms a purchase and expiry monitoring is armed. Recover pending purchase reuses the event and does not charge twice, including after a parent policy changes. New purchases require network access; existing shield state and scheduled expiry are local. If a receipt expires before activation, review it with the administrator; the app does not invent a refund or free time.

Parent code gates child selection/stop changes and works offline only after verifier setup/sync. It cannot prevent uninstall/reset or a compromised client. The server independently denies child self-awards and unauthorized policy changes.

An optional next-action Home Screen widget reuses the Live Activity extension and reads an atomic private App Group snapshot. Task titles are disabled by default and require explicit opt-in in Data tools. Calendar-day/staleness checks and privacy-sensitive rendering are implemented.

Successful unsigned compilation does not establish Family Controls provisioning, App Store distribution approval, or shield/expiry behavior on a signed iPhone. Free Personal Team signing support is not promised. Test locked/closed expiry, lost-response recovery, reboot/timezone changes, guardian flows, and data retention before relying on restrictions. This is a beta self-control/family tool, not tamper-proof device management.
