# Beta acceptance checklist

These device checks are deliberately unmarked until performed on your iPhone. A packaged IPA is not evidence that they passed.

## Automated build checks

- [ ] Pure Swift scheduling tests pass, including daily rollover, snooze, cancellation plans, capacity, DST, and persistence encoding.
- [ ] Native SwiftData tests pass in the simulator, including reopening a disk store with the same record IDs.
- [ ] Release arm64 device build succeeds without signing and packages as `Payload/OneStep.app`.
- [ ] IPA integrity and checksum checks pass; exactly the OneStepLive extension is embedded with its stable identifier.

## iPhone 12 with iOS 27

- [ ] Install beta build 1 through AltStore, launch, and enable reminders.
- [ ] Add a title-only task, close/reopen the app, edit it, and confirm persistence.
- [ ] Schedule a task two minutes ahead; lock the phone and turn networking off. Verify the alert, then tap it to open that task.
- [ ] Add a routine step due shortly. Mark Done after the due alert; verify its ten-minute follow-up does not arrive.
- [ ] Repeat with Skip Today. Snooze another step; verify only the snoozed alert arrives.
- [ ] Confirm the next local day shows the same routine with fresh completion state and yesterday's entry in History.
- [ ] Reopen after several missed steps; verify no burst of old alerts is created.
- [ ] Deny notifications in iPhone Settings; verify task/routine use remains available and settings explain the disabled reminders.
- [ ] Use a large accessibility text size and dark mode; verify the next action and buttons remain readable.
- [ ] Install build 2 over build 1 using the same AltStore account. Confirm tasks, templates, and history remain; check there are no duplicate alerts.
- [ ] Refresh through AltStore before expiry and confirm the app still opens with its data.

## Version 0.2 additions

- [ ] Install over the existing beta with the same signing account/identity and verify old tasks and history remain.
- [ ] Choose each of the six colors, relaunch, and confirm selection persists in both appearances.
- [ ] Start a focus timer, lock the phone, and verify countdown and expiry notification.
- [ ] Verify completing/snoozing/deleting the focused item cancels its timer notification.
- [ ] Start Show My Day and confirm current action, routine progress, and countdown on the iPhone 12 Lock Screen.
- [ ] Tap the Live Activity to open Now; stop it from the app.
- [ ] Keep the extension enabled in the signing tool and confirm Live Activity authorization. This has not been proven by the unsigned CI build alone.

## Version 0.4 family acceptance

Automated build results are recorded in BUILD-VERIFICATION.md. These real-account/device checks remain pending.

- [ ] Export a backup before updating; retain existing tasks/history after installing the main app over the same identity. Use the migration bridge first if the old identity is still installed.
- [ ] Enter the private service settings at runtime, enroll the owner once with its private key, and confirm meow and Application admin. Sign in on another client without reusing the enrollment key.
- [ ] Generate email-bound Parent/Kids beta keys. Confirm reused, expired, or wrong-email keys are rejected.
- [ ] Create a family, join with the separate short-lived invitation, assign a task, submit as child, and approve once as parent. Repeated approval must not award twice.
- [ ] Confirm child identity is email-only and absent from rankings; normal/parent opt-in shows only public profile fields.
- [ ] Configure an offline parent code, refresh Kids online, disconnect networking, and verify correct-code device sign-out and persisted failed-attempt lockout. Signing out must not unlink the family.
- [ ] Confirm a child cannot unlink itself or join a second family; the parent can unlink while retaining history.
- [ ] Reopen offline with the same account and inspect last-sync labels. Sign out/in as another account and confirm caches do not mix. Failed online actions must not silently award points.
- [ ] Verify locked-phone alerts and Live Activities with the signed main iPhone app; companion apps have no Live Activity extension.
