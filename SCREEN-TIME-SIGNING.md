# OneStep - signing for working Screen Time controls

Use the **Screen Time IPA** and a signing team that can issue profiles for its capabilities. Installing successfully is only the first check: the signed app, its embedded profiles, and its extensions must agree. OneStep does not need JIT or AltJIT.

With a free Personal Team, do not assume the necessary Family Controls and App Group profiles are available. Check the actual profiles. If they do not authorize these capabilities, choosing “preserve entitlements” cannot supply them; use the ordinary planner while arranging a capable developer team. Apple's development configuration uses the Apple Developer Program. Paid membership alone also does not establish distribution approval. [Apple: configure Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls), [capabilities by membership](https://developer.apple.com/help/account/reference/supported-capabilities-ios).

## 1. The three targets that must stay together

These are the current OneStep identifiers. Keep the existing signing team and app identity when updating so the installed app can retain its data. Export and verify a planner backup first.

| Target / bundle | Bundle identifier | Required capabilities for this build |
| --- | --- | --- |
| OneStep.app | meow.tira.onestep | Family Controls; App Group group.meow.tira.onestep |
| PlugIns/OneStepMonitor.appex | meow.tira.onestep.activitymonitor | Family Controls; the same App Group |
| PlugIns/OneStepLive.appex | meow.tira.onestep.liveactivity | The same App Group |

The main app and monitor use `OneStep/ScreenTime.entitlements`. The Live Activity/widget extension uses `OneStepLive/Shared.entitlements`. All three belong to the same Apple team. The ordinary IPA has no monitor and cannot provide OneStep's Screen Time blocking. Bank/Kids/Parent companion IPAs configure the account service; the blocking implementation is in the native main Screen Time app.

This table comes from the OneStep project. Apple's rule is that the application and each Screen Time API extension need their own appropriately configured profiles. [Apple configuration guide](https://developer.apple.com/documentation/xcode/configuring-family-controls).

## 2. Recommended route: Xcode on a Mac or your private cloud Mac

1. Open the OneStep source folder. Generate the capability-enabled project before changing signing settings:

```sh
export SCREEN_TIME_ENABLED=1
node scripts/generate-project.mjs
node scripts/generate-icon.mjs
open OneStep.xcodeproj
```

2. Add your Apple account in Xcode yourself. Select the same team for OneStep, OneStepMonitor and OneStepLive under Signing & Capabilities. Enable automatic signing, or select a matching profile for each target. Keep the version and build number consistent across all three targets; use the delivered build number or higher when making an update from source. Do not regenerate the project afterward without rechecking signing settings: the generator writes the project file.
3. Verify the three bundle identifiers in the table. Enable Family Controls for the main app and monitor App IDs, and register/associate the exact App Group with all three targets. Resolve signing errors before building. [Apple: enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/), [configure App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups).
4. Regenerate profiles after capability changes. Automatic signing can manage profile updates; manual signing requires fresh downloaded profiles for each affected target. A development/registered-device installation must include the intended iPhone in the appropriate device registrations/profile. [Development profiles](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile), [registered-device distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).
5. Run the signed app on the iPhone through Xcode, or archive and export using a development/debugging or registered-device Ad Hoc method supported by your profiles. Let Xcode sign the embedded extensions as well as the main app. The repository's `build-ipa.sh` deliberately produces an unsigned IPA; it is not the signed-export step.

For distribution, the Apple Developer Account Holder must request Family Controls distribution access for the main app **and** its Screen Time monitor extension. Check the assigned capability's Provisioning Support for the distribution method you intend to use, then refresh the profiles. [Apple: requesting Family Controls distribution](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).

## 3. If you sign the supplied IPA on Windows

Choose the filename ending in `-screen-time-unsigned.ipa`. Keep both extensions. Your signing tool must use your legitimate certificate/private key and appropriate per-bundle provisioning profiles, preserve the required entitlements, and sign every embedded target. A generic Apple-ID re-sign that removes App Groups or cannot provision Family Controls will not enable blocking.

Check the resulting identifiers and entitlements after the tool finishes. Do not silently change the app/group identifiers to satisfy a signer: that can break the shared container or create a different app identity. If a tool cannot handle these three targets/profiles, use the Xcode route above. There is no OneStep, AltStore, Sideloadly or JIT checkbox that overrides what Apple authorized in the profiles.

Keep certificates, private keys and profile files private. The public GitHub source and ordinary app connection key do not contain signing access.

## 4. Verify the final signed result

On a Mac, extract your **signed** IPA and inspect each bundle. These are read-only checks; replace the sample filename with your signed IPA:

```sh
ditto -xk Signed-OneStep.ipa Signed-OneStep
app="Signed-OneStep/Payload/OneStep.app"
for bundle in "$app" "$app/PlugIns/OneStepMonitor.appex" "$app/PlugIns/OneStepLive.appex"; do
  codesign --verify --strict --verbose=2 "$bundle"
  codesign --display --entitlements :- "$bundle"
  security cms -D -i "$bundle/embedded.mobileprovision" | \
    xmllint --xpath "/plist/dict/key[text()='Entitlements']/following-sibling::dict[position()=1]" -
done
```

Check `com.apple.developer.family-controls = true` in the main app and monitor signatures **and** their profiles. Check `com.apple.security.application-groups` authorizes `group.meow.tira.onestep` for all three. Application identifiers and team identifiers must match their profiles. Confirm certificate/profile validity and, for development/Ad Hoc, the intended device registration. Inspect the final re-signed output, since a later re-sign can alter a previously correct export. [Apple: diagnosing entitlement problems](https://developer.apple.com/documentation/bundleresources/diagnosing-issues-with-entitlements).

## 5. Enable and test on the iPhone

1. Install over the matching existing identity. In OneStep, open Bank > App time / Apple Screen Time and choose Authorize with Apple.
2. For self-control, use individual authorization. A child needs Apple's child/guardian authorization in the Family Sharing group; a OneStep family invitation or offline PIN does not replace that OS approval. [Apple authorization API](https://developer.apple.com/documentation/familycontrols/authorizationcenter/requestauthorization(for:)).
3. Choose an app, category or website, then apply blocking. Open the chosen target and verify the shield appears. The selector uses private Apple tokens; selecting a name alone does not prove enforcement.
4. After backend migration 006 is live, refresh the economy policy, verify the balance/allowance and redeem one point for one minute. Verify access during the unlock and that blocking returns after expiry, including while OneStep is closed/locked. Test parent settings gates and a lower child allowance separately.
5. Start a Live Activity from the planner. On iPhone 12, look on the Lock Screen; it does not have Dynamic Island. Live Activity controls still validate the exact current action/day. Private task titles and the current microstep/next title can be visible there, so use the system's Lock Screen privacy settings as appropriate.

## Troubleshooting

| What happens | What to check |
| --- | --- |
| OneStep says this copy needs another signing profile | Use the Screen Time variant; verify the shared group is present in the final app/profile and the group identifier was not rewritten. |
| Apple authorization fails | Check Family Controls in both main/monitor profiles, the signing team, and the correct individual/guardian flow. |
| Blocking works but timed re-lock does not | Verify the signed monitor extension is still embedded, has Family Controls and the shared group, and test monitor expiry on the device. |
| Points/XP show setup needed or redemption stays unavailable | Migration 006 is still pending or the service is unreachable. This is separate from Apple signing. See ECONOMY.md. |
| AltJIT reports a developer disk-image error | OneStep's release build does not need JIT; finish normal signing/provisioning instead. |
| An update is rejected for its application identifier | Recheck the original team and bundle identity; preserve the old app/verified backup while resolving the mismatch. |

**Current backend status:** migrations 001-005 are live. Migration 006 is tested and included, but has not been applied from this CLI session because Edge access is unavailable. Working Screen Time signing does not activate the new points/XP schema automatically.
