import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const projectDir = path.join(root, 'OneStep.xcodeproj');
fs.mkdirSync(path.join(projectDir, 'xcshareddata', 'xcschemes'), { recursive: true });
const id = name => crypto.createHash('sha256').update(name).digest('hex').slice(0, 24).toUpperCase();
const q = value => JSON.stringify(value);
const sources = ['Core/Planner.swift', 'Persistence.swift', 'Notifications.swift', 'Views.swift', 'OneStepApp.swift'];
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
object('app-group', `isa = PBXGroup; children = (${sources.map(file => id(`ref-${file}`)).join(',')},${id('assets-ref')},${id('info-ref')}); path = OneStep; sourceTree = "<group>";`);
object('tests-group', `isa = PBXGroup; children = (${tests.map(file => id(`test-ref-${file}`)).join(',')}); path = AppTests; sourceTree = "<group>";`);
object('products-group', `isa = PBXGroup; children = (${id('product-ref')},${id('test-product-ref')}); name = Products; sourceTree = "<group>";`);
object('main-group', `isa = PBXGroup; children = (${id('app-group')},${id('tests-group')},${id('products-group')}); sourceTree = "<group>";`);
object('sources-phase', `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${sources.map(file => id(`build-${file}`)).join(',')}); runOnlyForDeploymentPostprocessing = 0;`);
object('resources-phase', `isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (${id('assets-build')}); runOnlyForDeploymentPostprocessing = 0;`);
object('frameworks-phase', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;');
object('test-sources-phase', `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${tests.map(file => id(`test-build-${file}`)).join(',')}); runOnlyForDeploymentPostprocessing = 0;`);
object('test-frameworks-phase', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;');
object('proxy', `isa = PBXContainerItemProxy; containerPortal = ${id('project')}; proxyType = 1; remoteGlobalIDString = ${id('target')}; remoteInfo = OneStep;`);
object('dependency', `isa = PBXTargetDependency; target = ${id('target')}; targetProxy = ${id('proxy')};`);

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
  }; name = ${configuration};`);
  object(`target-${configuration}`, `isa = XCBuildConfiguration; buildSettings = {
    PRODUCT_BUNDLE_IDENTIFIER = tech.sillycat.onestep;
    PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1;
    INFOPLIST_FILE = OneStep/Info.plist; GENERATE_INFOPLIST_FILE = NO;
    ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
    ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
    CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = "";
    MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 1;
    SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
    SUPPORTS_MACCATALYST = NO; SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
  }; name = ${configuration};`);
  object(`test-${configuration}`, `isa = XCBuildConfiguration; buildSettings = {
    PRODUCT_BUNDLE_IDENTIFIER = tech.sillycat.onestep.tests;
    PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1;
    GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Automatic;
    TEST_HOST = "$(BUILT_PRODUCTS_DIR)/OneStep.app/OneStep";
    BUNDLE_LOADER = "$(TEST_HOST)";
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";
  }; name = ${configuration};`);
}
for (const kind of ['project', 'target', 'test']) {
  object(`${kind}-configs`, `isa = XCConfigurationList; buildConfigurations = (${id(`${kind}-Debug`)},${id(`${kind}-Release`)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;`);
}
object('target', `isa = PBXNativeTarget; buildConfigurationList = ${id('target-configs')}; buildPhases = (${id('sources-phase')},${id('frameworks-phase')},${id('resources-phase')}); buildRules = (); dependencies = (); name = OneStep; productName = OneStep; productReference = ${id('product-ref')}; productType = "com.apple.product-type.application";`);
object('test-target', `isa = PBXNativeTarget; buildConfigurationList = ${id('test-configs')}; buildPhases = (${id('test-sources-phase')},${id('test-frameworks-phase')}); buildRules = (); dependencies = (${id('dependency')}); name = OneStepTests; productName = OneStepTests; productReference = ${id('test-product-ref')}; productType = "com.apple.product-type.bundle.unit-test";`);
object('project', `isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = { ${id('target')} = { CreatedOnToolsVersion = 26.0; }; ${id('test-target')} = { CreatedOnToolsVersion = 26.0; TestTargetID = ${id('target')}; }; }; }; buildConfigurationList = ${id('project-configs')}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = ${id('main-group')}; productRefGroup = ${id('products-group')}; projectDirPath = ""; projectRoot = ""; targets = (${id('target')},${id('test-target')});`);
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
console.log('Generated OneStep.xcodeproj (one app target; tests are simulator-only).');
