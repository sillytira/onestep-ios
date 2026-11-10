# Beta limitations

- iOS 26 or newer; intended for iPhone 12 on iOS 27. Portrait layout only in this beta.
- Ordinary notifications only. No Critical Alerts, Time Sensitive entitlement, alarm override, or guarantee of sound through Focus/silent mode.
- At most 60 pending notifications are queued. Routines are generated for the next 14 days, but many daily steps can fill the queue sooner. Check the exact continuous coverage in reminder settings and reopen the app to refill it.
- The app cannot execute indefinitely while closed. No background refresh dependency, midnight daemon, or server is included. Daily completion resets when displaying each new local date; future notifications are pre-scheduled.
- Changing time zones requires reopening OneStep to rebuild routine times. DST changes are handled by calendar-based occurrence generation. A nonexistent spring-forward time moves to the next valid time; a repeated fall-back time uses the first occurrence.
- Due reminders and follow-ups already in the past are not replayed. A follow-up still in the future can fire even if you missed the first reminder. Late-night routine follow-ups do not cross midnight.
- Snooze is fixed at ten minutes. It changes reminder timing without changing task deadlines; routine snoozes stop at the end of today. Future tasks can be marked complete early.
- Due routines and tasks may alert at the same time. Alert coalescing and more sophisticated prioritization are deferred.
- Notification taps open the relevant current item. Completion/snooze actions are inside the app, not notification buttons.
- No timers, Live Activities, widgets, advanced repeating tasks, syncing, backup/import, or server deployment yet.
- Daily routine history remains after deleting a routine template. Completed tasks can be restored by swiping in History. Today's done/skip routine records cannot be undone in this beta.
- Deleting the app deletes all local data. Update in place using the same app identity and signing account.
- Free Apple ID installs expire unless refreshed through AltStore/AltServer. Signing and refreshing require connectivity even though daily app use does not.
- Cloud simulator tests do not establish real-device notification delivery or prove AltStore provisioning works. Complete the physical-device checklist in ACCEPTANCE.md.
