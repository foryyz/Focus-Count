from pathlib import Path
import hashlib
root=Path('apps/ios/FocusCount.xcodeproj')
def oid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
objects=[]
def obj(name,body): objects.append(f'{oid(name)} = {{ {body} }};'); return oid(name)
files=[];builds=[]
for p in sorted(Path('apps/ios/FocusCount').glob('*.swift')):
 f=obj(p.name,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {p.name}; sourceTree = "<group>";')
 b=obj('build'+p.name,f'isa = PBXBuildFile; fileRef = {f};');files.append(f);builds.append(b)
# Marker analytics and rendering are shared with the Mac target.
for name in ['EventAnalytics', 'MarkerOverviewData', 'MarkerPointLayout', 'MarkerColors', 'MarkerPointTimeline', 'MarkerFrequencyOverview', 'MarkerRangeNavigator', 'MarkerTimelineChart']:
 filename=name+'.swift'
 f=obj('portable-'+filename,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "../macos/Sources/FocusCount/{filename}"; sourceTree = SOURCE_ROOT;')
 b=obj('portable-build-'+filename,f'isa = PBXBuildFile; fileRef = {f};');files.append(f);builds.append(b)
info=obj('info','isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
files.append(info)
asset=obj('asset' ,'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
files.append(asset)
assetbuild=obj('assetbuild',f'isa = PBXBuildFile; fileRef = {asset};')
product=obj('product' ,'isa = PBXFileReference; explicitFileType = wrapper.application; path = FocusCount.app; sourceTree = BUILT_PRODUCTS_DIR;')
pkg=obj('package','isa = XCLocalSwiftPackageReference; relativePath = ../../packages/FocusCountCore;')
dep=obj('dep',f'isa = XCSwiftPackageProductDependency; package = {pkg}; productName = FocusCountCore;')
link=obj('link',f'isa = PBXBuildFile; productRef = {dep};')
sourcegroup=obj('sourcegroup',f'isa = PBXGroup; children = ({",".join(files)},); path = FocusCount; sourceTree = "<group>";')
products=obj('products',f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
main=obj('main',f'isa = PBXGroup; children = ({sourcegroup},{products},); sourceTree = "<group>";')
sources=obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks=obj('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({link},); runOnlyForDeploymentPostprocessing = 0;')
resources=obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({assetbuild},); runOnlyForDeploymentPostprocessing = 0;')
for mode in ['Debug','Release']:
 obj('project'+mode,f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; ONLY_ACTIVE_ARCH = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; }};')
 obj('target'+mode,f'''isa = XCBuildConfiguration; name = {mode}; buildSettings = {{
 ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; PRODUCT_NAME = FocusCount; PRODUCT_BUNDLE_IDENTIFIER = local.focuscount.ios;
 GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = FocusCount/Info.plist; INFOPLIST_KEY_CFBundleDisplayName = FocusCount;
 INFOPLIST_KEY_UIFileSharingEnabled = YES; INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES;
 INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
 INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
 TARGETED_DEVICE_FAMILY = 1; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
 SUPPORTS_MACCATALYST = NO; SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
 CURRENT_PROJECT_VERSION = 2; MARKETING_VERSION = 1.1.0; CODE_SIGN_STYLE = Automatic;
 ENABLE_DEBUG_DYLIB = NO; ENABLE_TESTABILITY = YES; SWIFT_EMIT_LOC_STRINGS = YES; SWIFT_OPTIMIZATION_LEVEL = "{'-Onone' if mode=='Debug' else '-O'}";
 SWIFT_ACTIVE_COMPILATION_CONDITIONS = "{'DEBUG' if mode=='Debug' else ''}";
 }};''')
for kind in ['project','target']:
 obj(kind+'configs',f'isa = XCConfigurationList; buildConfigurations = ({oid(kind+"Debug")},{oid(kind+"Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {oid("targetconfigs")}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = FocusCount; packageProductDependencies = ({dep},); productName = FocusCount; productReference = {product}; productType = "com.apple.product-type.application";')
testfile=obj('testfile','isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/PhoneStoreTests.swift; sourceTree = "<group>";')
# Add the test source to the root group for Xcode navigation.
objects[:] = [entry.replace(f"children = ({sourcegroup},{products},)", f"children = ({sourcegroup},{testfile},{products},)") for entry in objects]
testbuild=obj('testbuild',f'isa = PBXBuildFile; fileRef = {testfile};')
testsource=obj('testsource',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({testbuild},); runOnlyForDeploymentPostprocessing = 0;')
testproduct=obj('testproduct','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = FocusCountTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
objects[:] = [entry.replace(f"children = ({product},)", f"children = ({product},{testproduct},)") for entry in objects]
proxy=obj('proxy',f'isa = PBXContainerItemProxy; containerPortal = {oid("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = FocusCount;')
targetdep=obj('targetdep',f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
for mode in ['Debug', 'Release']:
 obj('tests'+mode, f'''isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ GENERATE_INFOPLIST_FILE = YES; PRODUCT_NAME = FocusCountTests; PRODUCT_BUNDLE_IDENTIFIER = local.focuscount.ios.tests; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/FocusCount.app/FocusCount"; BUNDLE_LOADER = "$(TEST_HOST)"; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; SWIFT_VERSION = 5.0; }};''')
testconfigs=obj('testconfigs', f'isa = XCConfigurationList; buildConfigurations = ({oid("testsDebug")},{oid("testsRelease")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
testlink=obj('testlink',f'isa = PBXBuildFile; productRef = {dep};')
testframeworks=obj('testframeworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({testlink},); runOnlyForDeploymentPostprocessing = 0;')
testtarget=obj('testtarget' ,f'isa = PBXNativeTarget; buildConfigurationList = {testconfigs}; buildPhases = ({testsource},{testframeworks},); packageProductDependencies = ({dep},); buildRules = (); dependencies = ({targetdep},); name = FocusCountTests; productName = FocusCountTests; productReference = {testproduct}; productType = "com.apple.product-type.bundle.unit-test";')
project=obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; }}; buildConfigurationList = {oid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; knownRegions = ("zh-Hans", en, Base,); mainGroup = {main}; productRefGroup = {products}; packageReferences = ({pkg},); projectDirPath = ""; projectRoot = ""; targets = ({target},{testtarget},);')
(root/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {project}; }}\n')
(root/'xcshareddata/xcschemes/FocusCount.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="FocusCount.app" BlueprintName="FocusCount" ReferencedContainer="container:FocusCount.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{testtarget}" BuildableName="FocusCountTests.xctest" BlueprintName="FocusCountTests" ReferencedContainer="container:FocusCount.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="FocusCount.app" BlueprintName="FocusCount" ReferencedContainer="container:FocusCount.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
