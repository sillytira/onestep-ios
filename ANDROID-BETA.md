# Android 0.9.0 Beta — build 14

This release updates only the Android planner APK. The native iPhone source and delivered IPA stay unchanged. The existing app identifier and permanent Android signing certificate are retained so the APK can update delivered 0.8 without uninstalling. Export a backup first.

## What changed

- Now, Tasks, Routines, Bank and More navigation; Material 3 controls, colored destination cards, short fade/slide tab changes and forward page transitions. System reduced motion disables tab motion.
- More brings over Notes, History, routine library/content updates, backups/restore, encrypted local Wi-Fi snapshots, family/account tools, and focused reminder settings. The Bank tab uses secondary chips rather than two bottom navigation bars.
- XP Beta has a dedicated progress screen, separate account XP and leaderboard access, pending-sync count and an explicit service/setup state. Ten XP per new signed-in task/routine completion, capped at 1,000 per UTC day; XP cannot buy app time. Account binding and replay protection remain intact. Children are not public ranking participants. Cached task/points rankings are never relabeled as XP rankings.
- Fixed the reported `PlatformException(invalid_icon)`: Android's release resource shrinker must preserve the drawable loaded by name. The generated Android project now includes a `res/raw/keep.xml` rule for `@drawable/ic_notification` and explicitly uses that icon for alerts.
- Ordinary notification permission and optional precise timing are separate. Denied permission shows actionable status. Standard alarms work without precise access; revocation during scheduling falls back to standard alarms. Serialized queue updates prevent save/resume operations from cancelling each other's reminders. Reminder settings include a real test-notification button.

## XP service activation

Migration 006 was not yet applied, as confirmed by the owner on November 16. Apply only `backend/006_economy_xp.sql` to the existing Supabase 001–005 project; never run the synthetic test scripts on production. It is already tested and does not change owner roles. Without it the planner works, and signed-in XP completion events remain pending rather than appearing as confirmed awards. The app cannot activate a missing backend schema by itself. See ECONOMY.md.

## Checking this APK

Install over your existing OneStep from the same release signing identity; do not uninstall your only saved planner. Open More → Reminders and settings, allow notifications and send a test reminder. Check OneStep's reminder-channel sound/banner settings if the test appears silently. Precise timing is optional; Android battery restrictions, Focus/Do Not Disturb and force-stop still affect delivery. Reopen after force-stop and periodically to extend the bounded reminder queue.

Apple Screen Time shielding, Live Activities and Apple widgets are platform-specific. This Android beta provides focus timers and reminders, not Android app blocking or an Apple API imitation. In-app content packs update routines; executable app changes still need a new APK.

## References

- [Plugin 19.5 Android release resource requirements](https://pub.dev/packages/flutter_local_notifications/versions/19.5.0#release-build-configuration)
- [Android precise-alarm permission behavior](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)
- [Flutter page transition guidance](https://docs.flutter.dev/cookbook/animation/page-route-animation)

Build/test evidence and device captures are delivered in the Android release folder. Widget renders are layout previews; emulator screenshots are labeled separately. Physical-phone acceptance remains necessary.
