# SnapNest

A native iOS project built with Swift and SwiftUI.

## Current stage

The runnable SwiftUI scaffold includes a local `CaptureCore` package with capture models and atomic SQLite storage. Saved image bytes and metadata can be reopened together. Camera/library capture, upload state transitions, and delivery are not connected yet; the screen remains the scaffold.

## Run

1. Open `SnapNest.xcodeproj` in Xcode (Xcode 16 or newer, Swift 6).
2. Select the `SnapNest` scheme and an iPhone simulator; press Run.
3. On a physical iPhone, select your signing team in Signing & Capabilities.

Minimum deployment target: iOS 17. No third-party runtime dependencies.

## Concepts and decisions

See [Concepts and decisions](docs/decisions.md) for plain-language explanations of the components and the choices behind them.

## Tests

Run `swift test` from the repository root. The current tests cover exponential retry delay, reopening committed image bytes and pending state, duplicate-save rollback, invalid/oversized input rejection, and byte-capacity rejection while preserving an existing capture.
