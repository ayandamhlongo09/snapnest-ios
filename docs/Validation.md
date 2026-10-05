# Validation

Checked on 5 October 2026 against the prepared native UI validation stage.

## Automated results

| Suite | Environment | Result |
| --- | --- | --- |
| CaptureCore (`swift test`) | macOS, Swift package | 20 passed; 0 failures |
| SnapNestUITests (`xcodebuild test`) | iPhone 18 Pro Max simulator, iOS 27.0 | 3 passed; 0 failures; 0 skipped |

The core tests cover atomic save/reopen/rollback, image and capacity limits, 10,000-record pagination, exclusive claims, interrupted-upload recovery, retry scheduling/manual retry, cleanup, persistent receipt deduplication and conflicts, worker cancellation, incorrect receipts, injected failures, and lost confirmation.

The native UI scenarios cover:

- Selecting a synthetic library image while demo offline, observing Waiting to send, turning demo offline off, observing Sent before relaunch, and checking the acceptance count remains unchanged after relaunch.
- Repeating the demo offline on/off cycle twice and checking the banner disappears.
- Reaching Choose photo by scrolling at maximum accessibility Dynamic Type.

The photo picker exposes an accessible photo element on the checked run. The test also retains the existing iOS 27 first-tile coordinate fallback; it depends on importing the fixture last into a dedicated test simulator.

## Progress screenshot

![Capture controls at maximum Dynamic Type](images/maximum-text.png)

Exported from the successful native UI test attachment and visually checked. The screenshot shows Choose photo reachable after scrolling; it does not establish full accessibility compliance.

## Boundaries and remaining validation

Delivery uses an in-app mock endpoint. Failures and confirmations exercise the real queue worker, but do not validate an HTTP server or packet-level upload resumption. Demo offline recovery does not prove host Wi-Fi interruption recovery.

Physical camera/permission behaviour, VoiceOver, real Wi-Fi interruption and recovery, iOS 17 runtime behaviour, and physical-device storage/memory behaviour remain unverified. The relaunch UI test terminates after successful confirmation; it is not a process-kill-during-write test. Process-kill stress evidence is planned for the next stage.

No production application changes were needed for this stage. The additions are the UI test target/shared scheme, existing test scenarios, synthetic fixture, documentation, and selected screenshot. Result bundles and build outputs remain local.
