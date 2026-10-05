# SnapNest

A native iOS project built with Swift and SwiftUI.

## Current stage

The runnable SwiftUI scaffold now includes a local `CaptureCore` package with capture models, queue states, upload payloads and receipts, errors, and the retry policy. Capture, storage, and delivery are not implemented yet.

## Run

1. Open `SnapNest.xcodeproj` in Xcode (Xcode 16 or newer, Swift 6).
2. Select the `SnapNest` scheme and an iPhone simulator; press Run.
3. On a physical iPhone, select your signing team in Signing & Capabilities.

Minimum deployment target: iOS 17. No third-party runtime dependencies.

## Concepts and decisions

See [Concepts and decisions](docs/decisions.md) for plain-language explanations of the components and the choices behind them.

## Tests

Run `swift test` from the repository root. The current test checks the existing exponential retry-delay policy and its 60-second cap.
