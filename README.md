# SnapNest

A native iOS project built with Swift and SwiftUI.

## Current stage

The runnable SwiftUI scaffold includes a local `CaptureCore` package with atomic SQLite storage and queue management: exclusive upload claims, persisted attempts and retry times, interrupted-upload recovery, manual retry, and sent-history cleanup. Storage bounds and metadata pagination are verified. Camera/library capture and the delivery worker are not connected yet; the screen remains the scaffold.

## Run

1. Open `SnapNest.xcodeproj` in Xcode (Xcode 16 or newer, Swift 6).
2. Select the `SnapNest` scheme and an iPhone simulator; press Run.
3. On a physical iPhone, select your signing team in Signing & Capabilities.

Minimum deployment target: iOS 17. No third-party runtime dependencies.

## Concepts and decisions

See [Concepts and decisions](docs/decisions.md) for plain-language explanations of the components and the choices behind them.

## Tests

Run `swift test` from the repository root. The current tests cover exponential retry delay, atomic persistence and rollback, input and capacity limits, the 10,000-record boundary and pagination, exclusive claims, interrupted-upload recovery, persisted retry timing, manual retry with the same capture ID, and sent-history cleanup that preserves pending captures.
