# SnapNest

A native iOS project built with Swift and SwiftUI.

## Current stage

The runnable SwiftUI scaffold includes a local `CaptureCore` package with atomic SQLite storage and queue management: exclusive upload claims, persisted attempts and retry times, interrupted-upload recovery, manual retry, and sent-history cleanup. Storage bounds and metadata pagination are verified. A mock endpoint now accepts captures and persists receipts, returning the original receipt for the same UUID and image digest while rejecting changed bytes under that UUID. It runs in-app with a separate receipt store when wired into the app; no live HTTP service is used. The serial upload coordinator now processes saved captures, validates confirmation, retries failures, and handles pause/resume and manual retry. Camera/library capture and app lifecycle integration are not connected yet; the screen remains the scaffold.

## Run

1. Open `SnapNest.xcodeproj` in Xcode (Xcode 16 or newer, Swift 6).
2. Select the `SnapNest` scheme and an iPhone simulator; press Run.
3. On a physical iPhone, select your signing team in Signing & Capabilities.

Minimum deployment target: iOS 17. No third-party runtime dependencies.

## Concepts and decisions

See [Concepts and decisions](docs/decisions.md) for plain-language explanations of the components and the choices behind them.

## Tests

Run `swift test` from the repository root. The current tests cover exponential retry delay, atomic persistence and rollback, input and capacity limits, the 10,000-record boundary and pagination, exclusive claims, interrupted-upload recovery, persisted retry timing, manual retry with the same capture ID, sent-history cleanup that preserves pending captures, receipt persistence/deduplication with conflict rejection across reopening, and coordinator success, automatic/manual retry, cancellation, incorrect receipts, lost confirmation, injected failures, and repeated saves/resumes.
