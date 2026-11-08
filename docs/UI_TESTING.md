# iOS UI Testing

CatVox uses a small native XCUITest suite for user-visible iOS smoke coverage.
The suite is intentionally separate from backend integration tests: UI tests run
with mocked app/backend state, while integration tests validate live Dev backend
contracts.

## Local Command

Run UI tests from the repository root:

```bash
make ios-ui-test
```

The target regenerates the Xcode project from `project.yml` and runs the
`CatVoxUITests` scheme on a concrete simulator destination. Override the
simulator when needed:

```bash
make ios-ui-test IOS_UI_TEST_DESTINATION="platform=iOS Simulator,name=iPhone 17,OS=26.5"
```

Pass the destination on the make command line. The Makefile assigns it with
`:=`, so an environment-variable prefix is silently ignored.

## Oldest Supported iOS

The Build workflow's `ios-floor` job runs this suite and the unit tests on the
app's deployment target: iOS 17.0 on an iPhone SE (2nd generation) simulator,
the smallest screen iOS 17 supports. It runs every Monday on `main` and on
manual dispatch, not on pull requests. A failed UI run there gets one retry,
because the first app launch on a new simulator can time out on a slow runner.
To run it on a branch:

```bash
gh workflow run build.yml --ref <branch>
```

To run the suite on iOS 17.0 locally, install the runtime first. It is a
7.56 GB download, so check free space with `df -h` before you start.

```bash
xcodebuild -downloadPlatform iOS -buildVersion 21A328
xcrun simctl create "iPhone SE (2nd generation)" "iPhone SE (2nd generation)" com.apple.CoreSimulator.SimRuntime.iOS-17-0
make ios-ui-test IOS_UI_TEST_DESTINATION="platform=iOS Simulator,name=iPhone SE (2nd generation),OS=17.0"
```

Remove the runtime afterwards with `xcrun simctl runtime delete <UUID>`, using
the UUID that `xcrun simctl runtime list` prints for build 21A328.

## Launch Arguments

The UI test target launches the app with:

| Argument | Purpose |
|---|---|
| `-uiTesting` | Enables deterministic UI-test mode, disables analytics, resets test-local state, and uses in-memory SwiftData storage. |
| `-mockBackend` | Forces upload/analysis flows that are reached during UI testing to use the in-app mock pipeline instead of Firebase, GCS, or Gemini. |
| `-seedHistory` | Seeds one deterministic local history item for history-replay coverage. |
| `-forceQuotaExceeded` | Starts the app with zero scans remaining so the quota/upgrade UI can be tested without backend calls. |

## Current Coverage

The first suite covers:

* Home launch smoke: primary CTA, history area, and quota/status text.
* Source choice: source actions are visible and the chooser can be dismissed.
* Seeded history replay: a saved scan opens the Result screen without upload or analysis.
* Mocked quota exceeded: the upgrade card renders without entering a real backend flow.

The suite does not use real camera capture, Photos picker content, user
accounts, Firebase App Check, GCS upload, Gemini/Vertex AI, network calls, local
absolute paths, screenshots, snapshot testing, Appium, Maestro, BrowserStack, or
Firebase Test Lab.

## Extension Path

The app state is controlled through launch arguments and app-owned seed data, so
the same tests can later run on real devices in Firebase Test Lab or BrowserStack
with minimal changes. Future cloud execution should keep the native XCUITest
bundle and pass the same launch arguments through the provider-specific test
runner rather than introducing a second automation framework.
