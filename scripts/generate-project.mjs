import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const bundleID = process.env.APP_BUNDLE_ID || 'meow.tira.onestep';
const screenTime = process.env.SCREEN_TIME_ENABLED === '1';
const projectDir = path.join(root, 'OneStep.xcodeproj');
fs.mkdirSync(path.join(projectDir, 'xcshareddata', 'xcschemes'), { recursive: true });
const id = name => crypto.createHash('sha256').update(name).digest('hex').slice(0, 24).toUpperCase();
const q = value => JSON.stringify(value);
const sources = ['Core/AppRoute.swift', 'ScreenTimeView.swift', 'PersonalRewards.swift', 'Shared/ScreenTimeState.swift', 'Shared/WidgetSnapshot.swift', 'Core/Planner.swift', 'Core/RewardsRules.swift', 'Core/Content.swift', 'ContentUpdates.swift', 'Shared/DayActionIntent.swift', 'Core/Transfer.swift', 'LocalTransfer.swift', 'Account.swift', 'DataToolsView.swift', 'RewardsView.swift', 'Persistence.swift', 'Notifications.swift', 'Views.swift', 'OneStepApp.swift', 'FocusTimerSheet.swift', 'LiveActivities.swift', 'Shared/Palette.swift', 'Shared/DayActivityAttributes.swift'];
const tests = ['PlannerStoreTests.swift'];
const objects = [];
const object = (name, body) => objects.push(`${id(name)} = { ${body} };`);
for (const file of sources) {
  object(`ref-${file}`, `isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${q(file)}; sourceTree = "<group>";`);
  object(`build-${file}`, `isa = PBXBuildFile; fileRef = ${id(`ref-${file}`)};`);
}
for (const file of tests) {
  object(`test-ref-${file}`, `isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${q(file)}; sourceTree = "<group>";`);
  object(`test-build-${file}`, `isa = PBXBuildFile; fileRef = ${id(`test-ref-${file}`)};`);
}
object('assets-ref', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";');
object('assets-build', `isa = PBXBuildFile; fileRef = ${id('assets-ref')};`);
object('info-ref', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";');
object('product-ref', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = OneStep.app; sourceTree = BUILT_PRODUCTS_DIR;');
object('test-product-ref', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = OneStepTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;');
object('live-product-ref', 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = OneStepLive.appex; sourceTree = BUILT_PRODUCTS_DIR;');
object('live-source-ref', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = OneStepLive.swift; sourceTree = "<group>";');
object('live-info-ref', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";');
object('live-source-build', `isa = PBXBuildFile; fileRef = ${id('live-source-ref')};`);
object('live-palette-build', `isa = PBXBuildFile; fileRef = ${id('ref-Shared/Palette.swift')};`);
object('live-attributes-build', `isa = PBXBuildFile; fileRef = ${id('ref-Shared/DayActivityAttributes.swift')};`);
object('live-intent-build', `isa = PBXBuildFile; fileRef = ${id('ref-Shared/DayActionIntent.swift')};`);
object('live-embed-build', `isa = PBXBuildFile; fileRef = ${id('live-product-ref')}; settings = { ATTRIBUTES = (RemoveHeadersOnCopy); };`);
object('live-group', `isa = PBXGroup; children = (${id('live-source-ref')},${id('live-info-ref')}); path = OneStepLive; sourceTree = "<group>";`);
object('app-group', `isa = PBXGroup; children = (${sources.map(file => id(`ref-${file}`)).join(',')},${id('assets-ref')},${id('info-ref')}); path = OneStep; sourceTree = "<group>";`);
object('tests-group', `isa = PBXGroup; children = (${tests.map(file => id(`test-ref-${file}`)).join(',')}); path = AppTests; sourceTree = "<group>";`);
object('live-widget-build', `isa = PBXBuildFile; fileRef = ${id('ref-Shared/WidgetSnapshot.swift')};`);
if(screenTime){
 object('monitor-ref','isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = OneStepMonitor.swift; sourceTree = "<group>";');
 object('monitor-info','isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";');
 object('monitor-product','isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = OneStepMonitor.appex; sourceTree = BUILT_PRODUCTS_DIR;');
 object('monitor-build',`isa = PBXBuildFile; fileRef = ${id('monitor-ref')};`);
 object('monitor-shared-build',`isa = PBXBuildFile; fileRef = ${id('ref-Shared/ScreenTimeState.swift')};`);
 object('monitor-rules-build',`isa = PBXBuildFile; fileRef = ${id('ref-Core/RewardsRules.swift')};`);
 object('monitor-embed',`isa = PBXBuildFile; fileRef = ${id('monitor-product')}; settings = { ATTRIBUTES = (RemoveHeadersOnCopy); };`);
 object('monitor-group',`isa = PBXGroup; children = (${id('monitor-ref')},${id('monitor-info')}); path = OneStepMonitor; sourceTree = "<group>";`);
 object('monitor-sources',`isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${id('monitor-build')},${id('monitor-rules-build')},${id('monitor-shared-build')}); runOnlyForDeploymentPostprocessing = 0;`);
 object('monitor-frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;');
 object('monitor-copy',`isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = (${id('monitor-embed')}); name = "Embed Activity Monitor"; runOnlyForDeploymentPostprocessing = 0;`);
 object('monitor-proxy',`isa = PBXContainerItemProxy; containerPortal = ${id('project')}; proxyType = 1; remoteGlobalIDString = ${id('monitor-target')}; remoteInfo = OneStepMonitor;`);
 object('monitor-dependency',`isa = PBXTargetDependency; target = ${id('monitor-target')}; targetProxy = ${id('monitor-proxy')};`);
}
object('products-group', `isa = PBXGroup; children = (${id('product-ref')},${id('test-product-ref')},${id('live-product-ref')}${screenTime ? ','+id('monitor-product') : ''}); name = Products; sourceTree = "<group>";`);
object('main-group', `isa = PBXGroup; children = (${id('app-group')},${id('tests-group')},${id('live-group')}${screenTime ? ','+id('monitor-group') : ''},${id('products-group')}); sourceTree = "<group>";`);
object('sources-phase', `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${sources.map(file => id(`build-${file}`)).join(',')}); runOnlyForDeploymentPostprocessing = 0;`);
object('resources-phase', `isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (${id('assets-build')}); runOnlyForDeploymentPostprocessing = 0;`);
object('frameworks-phase', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;');
object('test-sources-phase', `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${tests.map(file => id(`test-build-${file}`)).join(',')}); runOnlyForDeploymentPostprocessing = 0;`);
object('test-frameworks-phase', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;');
object('live-sources-phase', `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${id('live-source-build')},${id('live-widget-build')},${id('live-intent-build')},${id('live-palette-build')},${id('live-attributes-build')}); runOnlyForDeploymentPostprocessing = 0;`);
object('live-frameworks-phase', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;');
object('live-copy-phase', `isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = (${id('live-embed-build')}); name = "Embed Live Activity"; runOnlyForDeploymentPostprocessing = 0;`);
object('proxy', `isa = PBXContainerItemProxy; containerPortal = ${id('project')}; proxyType = 1; remoteGlobalIDString = ${id('target')}; remoteInfo = OneStep;`);
object('dependency', `isa = PBXTargetDependency; target = ${id('target')}; targetProxy = ${id('proxy')};`);
object('live-proxy', `isa = PBXContainerItemProxy; containerPortal = ${id('project')}; proxyType = 1; remoteGlobalIDString = ${id('live-target')}; remoteInfo = OneStepLive;`);
object('live-dependency', `isa = PBXTargetDependency; target = ${id('live-target')}; targetProxy = ${id('live-proxy')};`);

for (const configuration of ['Debug', 'Release']) {
  const debug = configuration === 'Debug';
  object(`project-${configuration}`, `isa = XCBuildConfiguration; buildSettings = {
    CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES;
    IPHONEOS_DEPLOYMENT_TARGET = 26.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0;
    SWIFT_STRICT_CONCURRENCY = targeted;
    DEBUG_INFORMATION_FORMAT = ${debug ? 'dwarf' : '"dwarf-with-dsym"'};
    SWIFT_OPTIMIZATION_LEVEL = ${debug ? '"-Onone"' : '"-O"'};
    SWIFT_ACTIVE_COMPILATION_CONDITIONS = ${debug ? 'DEBUG' : '""'};
    ENABLE_TESTABILITY = ${debug ? 'YES' : 'NO'};
    ONLY_ACTIVE_ARCH = ${debug ? 'YES' : 'NO'};
  }; name = ${configuration};`);
  object(`target-${configuration}`, `isa = XCBuildConfiguration; buildSettings = {
    PRODUCT_BUNDLE_IDENTIFIER = ${bundleID};
    PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1;
    INFOPLIST_FILE = OneStep/Info.plist; GENERATE_INFOPLIST_FILE = NO;
    SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) ONESTEP_APP";
    ONESTEP_SCREEN_TIME_ENABLED = ${screenTime ? "YES" : "NO"};
    ${screenTime ? "CODE_SIGN_ENTITLEMENTS = OneStep/ScreenTime.entitlements;" : ""}
    ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
    ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
    CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = "";
    MARKETING_VERSION = 0.7.0; CURRENT_PROJECT_VERSION = 5;
    SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
    SUPPORTS_MACCATALYST = NO; SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
  }; name = ${configuration};`);
  object(`live-${configuration}`, `isa = XCBuildConfiguration; buildSettings = {
    PRODUCT_BUNDLE_IDENTIFIER = ${bundleID}.liveactivity;
    PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1;
    INFOPLIST_FILE = OneStepLive/Info.plist; GENERATE_INFOPLIST_FILE = NO;
    ${screenTime ? "CODE_SIGN_ENTITLEMENTS = OneStepLive/Shared.entitlements;" : ""}
    APPLICATION_EXTENSION_API_ONLY = YES; SKIP_INSTALL = YES;
    CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = "";
    MARKETING_VERSION = 0.7.0; CURRENT_PROJECT_VERSION = 5;
    SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
    SUPPORTS_MACCATALYST = NO;
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks";
  }; name = ${configuration};`);
  object(`test-${configuration}`, `isa = XCBuildConfiguration; buildSettings = {
    PRODUCT_BUNDLE_IDENTIFIER = ${bundleID}.tests;
    PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1;
    GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Automatic;
    TEST_HOST = "$(BUILT_PRODUCTS_DIR)/OneStep.app/OneStep";
    BUNDLE_LOADER = "$(TEST_HOST)";
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";
  }; name = ${configuration};`);
}
if(screenTime){
 for(const configuration of ['Debug','Release']) object('monitor-'+configuration, `isa = XCBuildConfiguration; buildSettings = { PRODUCT_BUNDLE_IDENTIFIER = ${bundleID}.activitymonitor; PRODUCT_NAME = "$(TARGET_NAME)"; INFOPLIST_FILE = OneStepMonitor/Info.plist; GENERATE_INFOPLIST_FILE = NO; IPHONEOS_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 5.0; APPLICATION_EXTENSION_API_ONLY = YES; SKIP_INSTALL = YES; MARKETING_VERSION = 0.7.0; CURRENT_PROJECT_VERSION = 5; CODE_SIGN_ENTITLEMENTS = OneStep/ScreenTime.entitlements; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = ""; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"; }; name = ${configuration};`);
 object('monitor-target',`isa = PBXNativeTarget; buildConfigurationList = ${id('monitor-configs')}; buildPhases = (${id('monitor-sources')},${id('monitor-frameworks')}); buildRules = (); dependencies = (); name = OneStepMonitor; productName = OneStepMonitor; productReference = ${id('monitor-product')}; productType = "com.apple.product-type.app-extension";`);
}
for (const kind of ['project', 'target', 'test', 'live', ...(screenTime ? ['monitor'] : [])]) {
  object(`${kind}-configs`, `isa = XCConfigurationList; buildConfigurations = (${id(`${kind}-Debug`)},${id(`${kind}-Release`)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;`);
}
object('target', `isa = PBXNativeTarget; buildConfigurationList = ${id('target-configs')}; buildPhases = (${id('sources-phase')},${id('frameworks-phase')},${id('resources-phase')},${id('live-copy-phase')}${screenTime ? ','+id('monitor-copy') : ''}); buildRules = (); dependencies = (${id('live-dependency')}${screenTime ? ','+id('monitor-dependency') : ''}); name = OneStep; productName = OneStep; productReference = ${id('product-ref')}; productType = "com.apple.product-type.application";`);
object('test-target', `isa = PBXNativeTarget; buildConfigurationList = ${id('test-configs')}; buildPhases = (${id('test-sources-phase')},${id('test-frameworks-phase')}); buildRules = (); dependencies = (${id('dependency')}); name = OneStepTests; productName = OneStepTests; productReference = ${id('test-product-ref')}; productType = "com.apple.product-type.bundle.unit-test";`);
object('live-target', `isa = PBXNativeTarget; buildConfigurationList = ${id('live-configs')}; buildPhases = (${id('live-sources-phase')},${id('live-frameworks-phase')}); buildRules = (); dependencies = (); name = OneStepLive; productName = OneStepLive; productReference = ${id('live-product-ref')}; productType = "com.apple.product-type.app-extension";`);
object('project', `isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = { ${id('target')} = { CreatedOnToolsVersion = 26.0; }; ${id('test-target')} = { CreatedOnToolsVersion = 26.0; TestTargetID = ${id('target')}; }; ${id('live-target')} = { CreatedOnToolsVersion = 26.0; }; }; }; buildConfigurationList = ${id('project-configs')}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = ${id('main-group')}; productRefGroup = ${id('products-group')}; projectDirPath = ""; projectRoot = ""; targets = (${id('target')},${id('test-target')},${id('live-target')}${screenTime ? ','+id('monitor-target') : ''});`);
fs.writeFileSync(path.join(projectDir, 'project.pbxproj'), `// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n${objects.join('\n')}\n}; rootObject = ${id('project')}; }\n`);

const buildable = (target, name, product) => `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id(target)}" BuildableName="${product}" BlueprintName="${name}" ReferencedContainer="container:OneStep.xcodeproj"/>`;
fs.writeFileSync(path.join(projectDir, 'xcshareddata/xcschemes/OneStep.xcscheme'), `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${buildable('target', 'OneStep', 'OneStep.app')}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">${buildable('test-target', 'OneStepTests', 'OneStepTests.xctest')}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${buildable('target', 'OneStep', 'OneStep.app')}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">${buildable('target', 'OneStep', 'OneStep.app')}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n`);
console.log('Generated OneStep.xcodeproj (app + one Live Activity extension; tests are simulator-only).');
