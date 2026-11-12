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
- [ ] Sign in to the built-in main service, enroll the owner once with its private key, and confirm meow and Application admin. Sign in on another client without reusing the enrollment key.
- [ ] Generate email-bound Parent/Kids beta keys. Confirm reused, expired, or wrong-email keys are rejected.
- [ ] Create a family, join with the separate short-lived invitation, assign a task, submit as child, and approve once as parent. Repeated approval must not award twice.
- [ ] Confirm child identity is email-only and absent from rankings; normal/parent opt-in shows only public profile fields.
- [ ] Configure an offline parent code, refresh Kids online, disconnect networking, and verify correct-code device sign-out and persisted failed-attempt lockout. Signing out must not unlink the family.
- [ ] Confirm a child cannot unlink itself or join a second family; the parent can unlink while retaining history.
- [ ] Reopen offline with the same account and inspect last-sync labels. Sign out/in as another account and confirm caches do not mix. Failed online actions must not silently award points.
- [ ] Verify locked-phone alerts and Live Activities with the signed main iPhone app; companion apps have no Live Activity extension.

## Version 0.5 content and routine acceptance

- [ ] Install 0.5 once over the existing identity. Open Bank/companion login directly with no URL/key setup.
- [ ] Check content, inspect pack steps, add a pack, relaunch offline, and confirm cached content and duplicate prevention. Publish a higher content-only revision and confirm it appears without rebuilding or resigning the app.
- [ ] Finish or skip one routine step, undo it today, and confirm history on earlier days remains. Change an incomplete step’s time today and confirm tomorrow/task deadlines are unchanged.
- [ ] Start a portable guided routine and complete/skip steps in sequence; snoozed steps are set aside.
- [ ] Verify coincident task/routine reminders share a banner and completing all referenced steps removes pending reminders. Check queue coverage and regular refill.
- [ ] Add the OneStep shortcuts widget. Verify Now/Routines/Add/Timer destinations. Start a Live Activity and test Done/Snooze after device authentication; stale/previous-day actions must not affect another task.
- [ ] Verify Time Sensitive is unavailable or falls back safely when absent from provisioning, and ordinary notifications continue.

## Version 0.6 rewards and Screen Time acceptance

- [ ] Enroll a normal-account task with a chosen 0–100 reward; finish it offline and reopen online. Verify server credit once after the minimum age, duplicate-title filter, and displayed pending state. A second account must not claim its enrollment.
- [ ] Verify UTC daily caps of 20 counted tasks and 500 earned points; switch weekly ranking metrics and confirm child identities, admin grants, and spending never increase earned rankings.
- [ ] Reload a parent's saved app-time policy, select another child, change price/limit, and confirm independent settings persist. Child purchases must show cost; a changed price must reject before debit.
- [ ] Provision the Screen Time variant with Family Controls/App Groups and authorize Apple individual/family mode. Select an app and verify its shield, then a paid timed unlock and automatic re-blocking while the app is closed and phone locked.
- [ ] Lose a purchase response, recover the same receipt without a second debit, and verify expired receipts do not create free time. Test reboot/timezone changes and guardian/parent-code settings gates.
- [ ] Enable private widget titles explicitly, verify next action/stale-day fallback, then disable sharing and confirm the widget no longer reveals a title.
- [ ] Install delivered 0.6 over delivered 0.5 with matching Apple identity/Android certificate; retain tasks and history. Export a backup first.

## Version 0.7 repair acceptance

- [ ] Verify Add task, completion, snooze, routine history, restart retention, and reminders in the installed apps. Export first.
- [ ] Open Bank from the iPhone tab/desktop sidebar. Switch Home/Activity/Rankings/Account; verify the statement contains only the current account, even for a parent.
- [ ] Reconnect an expired session with the same account password, preserving family links and local tasks. Check that old manual server settings cannot redirect the app.
- [ ] Edit a parent app-time policy, wait through a background refresh, then save. Verify the edit and selected child persist.
- [ ] Follow onestep://bank and widget/Live Activity links with the app already open and after a cold start.
- [ ] Use large text and a narrow desktop window; verify navigation, scrolling and actions remain reachable.
- [ ] On a properly signed Screen Time variant, authorize Apple access, select apps/categories/websites, apply shields, purchase an unlock, and verify re-blocking. Ordinary builds must show the explicit setup requirement.

## Detailed Live Activity acceptance

- Start an activity on the signed iPhone and check current title, microstep/next hint, tasks done/open, routine Done/Skip progress, due/focus time, and selected snooze duration.
- Pause/resume a duration focus timer, verify a static paused time, then test Done/Snooze from the Lock Screen against the exact task/day.
- Check large text, stale snapshots, next-day ending and system lifetime limits. The rendered simulator card and payload tests do not prove delivery/interaction on the physical phone.
- Confirm the three targets' profiles using SCREEN-TIME-SIGNING.md. Keep the old app/verified export until update retention is checked.
