# SnapNest

A native iOS project built with Swift and SwiftUI.

## Current stage

The app now supports native camera and photo-library capture, image preparation, and saving before delivery. A shared core package provides SQLite persistence, bounded queue management, idempotent mock receipts, and serial automatic retries. Startup, lifecycle, and connectivity are connected. The capture and queue interface now shows saved items, waiting/sent counts, upload states, manual Retry, paginated history, and sent-history cleanup. Disconnection feedback includes Check connection. Reviewer failure controls are now available from the sliders button, including simulated offline mode, dropped requests, latency, server errors, and lost confirmation after acceptance.

## Run

1. Open `SnapNest.xcodeproj` in Xcode (Xcode 16 or newer, Swift 6).
2. Select the `SnapNest` scheme and an iPhone simulator; press Run.
3. On a physical iPhone, select your signing team in Signing & Capabilities.
4. Choose Selfie or Identity document, then Take photo or Choose photo. Camera availability depends on the device; the library can be used on a simulator.
5. Open Demo controls from the sliders button to change request failure settings at runtime and inspect the unique acceptance count.

Minimum deployment target: iOS 17. No third-party runtime dependencies.

## Concepts and decisions

See [Concepts and decisions](docs/decisions.md) for plain-language explanations of the components and the choices behind them.

## Tests

Run `swift test` from the repository root. The current tests cover exponential retry delay, atomic persistence and rollback, input and capacity limits, the 10,000-record boundary and pagination, exclusive claims, interrupted-upload recovery, persisted retry timing, manual retry with the same capture ID, sent-history cleanup that preserves pending captures, receipt persistence/deduplication with conflict rejection across reopening, and coordinator success, automatic/manual retry, cancellation, incorrect receipts, lost confirmation, injected failures, and repeated saves/resumes.

Delivery runs while the app is active, the OS reports a satisfied network path, and demo offline mode is disabled. It pauses on inactivity or disconnection and recovers interrupted work on foreground entry. The endpoint remains an in-app mock; network-path availability is not proof that a remote service is reachable. Physical Wi-Fi interruption/recovery remains a manual validation gap.

## Progress evidence

![SnapNest capture screen](docs/images/capture-screen.png)

Capture screen after adding native photo capture controls. Checked on the iPhone 18 Pro Max simulator, iOS 27. This records the capture-screen stage. Later native picker/upload validation is documented in [Validation](docs/Validation.md); physical camera validation remains outstanding.

![SnapNest queue interface](docs/images/queue-screen.png)

Queue interface after adding history and status controls, shown with an empty queue on the iPhone 18 Pro Max simulator, iOS 27. Build and launch passed; this screenshot does not validate populated states or the end-to-end upload flow.

## Reviewer failure controls

| Control | Simulated behaviour |
| --- | --- |
| Go offline | Pauses/cancels delivery while keeping captures saved. Turn it off to re-evaluate connectivity and resume. |
| Drop uploads | Each request has the selected probability of failing before acceptance (0–100%). |
| Delay | Adds 0–15 seconds before processing each request. |
| Server errors (503) | Produces the mock service-busy error; no actual HTTP response is sent. |
| Lose response after acceptance | Commits the receipt, then reports interrupted confirmation to the client. |

Settings apply to the next request; offline cancels the current worker. They reset on full relaunch while captures and receipts persist. Endpoint evidence shows the number of unique accepted IDs; repeated requests with the same ID and bytes return the existing receipt. The existing core tests cover forced offline/drop/server failures and response-loss deduplication; native controls and capture-flow UI tests are now included in the Xcode scheme. See [Validation](docs/Validation.md) for results and limitations.

## Native UI validation

The shared SnapNest scheme includes `UITests/SnapNestUITests.swift`. Import the synthetic fixture into the test simulator last, then use Product → Test in Xcode or run:

```sh
xcrun simctl addmedia booted fixtures/demo-document.png
xcodebuild -project SnapNest.xcodeproj -scheme SnapNest -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' test
```

The library test has an iOS 27 coordinate fallback for the first tile when the system picker omits its grid from the accessibility snapshot. Use a dedicated test simulator and the fixture setup above. See [Validation](docs/Validation.md) for the checked environment, results, and remaining gaps.

![SnapNest at maximum accessibility text size](docs/images/maximum-text.png)

Progress evidence from the successful maximum Dynamic Type UI test. Choose photo remains reachable after scrolling. On 5 October 2026, all 20 core tests and all 3 native UI tests passed; [Validation](docs/Validation.md) records the scope and remaining gaps.

## Process-kill persistence check

```sh
swift build --product QueueProbe
python3 scripts/crash_stress.py
```

The macOS probe writes 1 MiB captures through the real QueueStore. The script kills it at 12 different delays, reopens each temporary database, and checks integrity, acknowledged IDs, image lengths, sizes, and pending state. All 12 runs passed on 5 October 2026. This validates the shared persistence implementation under process termination; it does not establish the exact interruption point or physical iOS force-quit behaviour. See [Validation](docs/Validation.md).
