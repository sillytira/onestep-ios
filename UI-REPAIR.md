# 0.7 usability and reliability repair

The user reported that the previous release broadly failed in use. This repair addresses concrete code/UI defects; compilation and synthetic checks are recorded separately from physical-phone acceptance.

## Repairs

- Shared per-process account clients and serialized token rotation prevent planner rewards, Bank, and Screen Time from independently rotating the same refresh token. Old manual connection values no longer override the built-in service. Reconnect uses the existing account email without unlinking a child.
- Bank transactions explicitly filter by the signed-in user, so a parent's family read permissions cannot mix child ledger entries into the parent's personal statement. Cached account data remains usable when optional service sections fail.
- Separate Bank Home, Activity, Rankings, and Account views replace the form wall. Family work has its own destination in the portable companions. Accounts and points are virtual, with no payment-card or cash claims.
- Native Bank has a direct main tab; More provides Notes, History, Screen Time, backups, and settings. Apple navigation/controls use the system material; balance/content cards use regular backgrounds rather than glass.
- Desktop has an adaptive sidebar, branded workspace, a direct Add task button, Bank shortcut, and clearer date/header styles. Narrow windows retain bottom navigation.
- Parent policy edits survive background refresh until saved; child selection stays consistent. Task edits preserve existing reward enrollment when the account is unavailable. Empty task titles produce visible feedback.
- Screen Time presents a clear unsupported-build state, selected app/category/website counts, authorization and blocking status, and reconnect guidance. Category selection now shields website categories too. Shield state is saved before stopping its monitor. Parent settings authorization is cleared when leaving the foreground.

## Primary references used

- [Apple materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials): glass belongs to navigation and controls, with readable content surfaces.
- [Family Controls authorization](https://developer.apple.com/documentation/familycontrols/authorizationcenter/requestauthorization(for:)): individual and child/guardian authorization differ; app account roles do not replace Apple's family authorization.
- [ManagedSettings ShieldSettings](https://developer.apple.com/documentation/managedsettings/shieldsettings): application, web-domain, and category shielding.
- [DeviceActivity monitoring](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)): monitor callbacks, schedule replacement, and errors.
- [ActivityKit live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities): widget-extension presentation, app-intent actions, runtime authorization, and system limits.
- [Microsoft adaptive navigation](https://learn.microsoft.com/en-us/windows/apps/design/controls/navigationview): expanded/compact navigation that adapts to window width.
- [Revolut's official design reference](https://www.revolut.com/news/revolut_launches_revolut_10_as_it_targets_primary_accounts_and_passes_35m_customers_worldwide/): balance-first home, clear account/activity structure and quick access. OneStep uses original visuals and virtual rewards.

The Apple Screen Time variant still needs appropriate Family Controls/App Group profiles and real-device authorization. No UI change can manufacture those capabilities in an ordinary free-signing profile. Offline planner/reminders are independent of this requirement. Real account credentials are entered only by the user; test sessions and balances are synthetic.
