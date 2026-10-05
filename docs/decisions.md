# Concepts and decisions

This document explains the concepts and choices as their components are introduced.

## Native iOS foundation

**Concept**
The assessment requires a native mobile application. The app interface and shared logic have different responsibilities.

**Decision**
Use Swift and SwiftUI with an iOS 17 minimum deployment target. Keep platform-independent models and delivery logic in a local `CaptureCore` Swift package. Its macOS 14 support allows the existing core tests to run on this Mac. There are no third-party runtime dependencies. iOS-specific camera, lifecycle, and UI integration belong in the app.

## Capture identity and image data

**Concept**
A capture needs one identity throughout saving, sending, and retrying. Loading every saved image just to display a history list would waste memory.

**Decision**
Use a UUID for each capture and preserve it across attempts. `CaptureItem` describes history metadata without image bytes; `UploadPayload` carries the image for delivery. The types distinguish selfies from document photos. Storage and delivery will implement these contracts in subsequent steps.

## Queue states

**Concept**
Saving a photo, attempting delivery, and receiving confirmation are different events. An unsuccessful attempt must not imply the photo was lost.

**Decision**
Define four states: `pending`, `uploading`, `uploaded`, and `failed`. Capture metadata includes attempts, the next eligible attempt time, and an explanatory message. `QueueSummary` provides counts and outstanding image bytes for the interface. The persistence and upload components will implement the transitions later; defining the states alone does not provide recovery.

## Delivery confirmation

**Concept**
A response must identify which capture was accepted and which image bytes it refers to. A retry after a lost response can otherwise create a duplicate.

**Decision**
Represent confirmation with an `UploadReceipt` containing the capture UUID and image digest. The later worker will validate both before marking a capture uploaded, and the mock receiver will deduplicate repeated requests. This step defines the receipt; it does not yet calculate digests or send requests.

## Retry policy

**Concept**
Repeated immediate attempts can overload an unavailable service. Automatic attempts also need a limit so persistent failures remain visible and actionable.

**Decision**
Use the existing policy of five automatic attempts, starting with a two-second retry delay and doubling subsequent delays. The delay function caps at 60 seconds; the five-attempt budget normally uses delays of 2, 4, 8, and 16 seconds. Manual retry will renew the budget when the coordinator is introduced. The existing unit test verifies exponential delay and the cap. Deterministic delays keep this prototype simple; fleet-wide retry jitter is not implemented.

## Durable photo storage

**Concept**
A captured photo must survive an app restart before delivery is attempted. “Saved” means its bytes and queue metadata have committed to disk. A photo still held in memory has not crossed that boundary.

**Decision**
Store image bytes, UUID, capture type, timestamp, and pending state together in one SQLite transaction. `BEGIN IMMEDIATE` starts the write transaction; the capacity check and insert happen inside it; `COMMIT` completes the save. A failure rolls the transaction back. This avoids coordinating separate image files with metadata. A duplicate ID is rejected without overwriting the original capture. The existing tests verify reopened bytes/state and rollback. Process-kill validation will be introduced in its planned later step.

## SQLite ownership and durability

**Concept**
Concurrent operations must not interleave halfway through a transaction, and the database connection must remain valid until its owner finishes using it.

**Decision**
Give one `QueueStore` actor ownership of one SQLite connection. Database operations are synchronous within the actor, so a transaction has no suspension point where another actor call can interleave. A private connection holder closes the handle when ownership ends; its narrow `@unchecked Sendable` declaration relies on this confinement. Use SQLite's DELETE rollback journal and FULL synchronization to prioritise committed-save durability over write throughput. These mechanisms do not protect against app uninstall, device loss, or arbitrary filesystem corruption.

## Storage bounds and reads

**Concept**
Image storage can consume disk space quickly. Rejecting a new capture must preserve the photos already saved. History reads should avoid loading all image bytes into memory.

**Decision**
Reuse the existing save-time limits: 10,000 total capture records, 512 MiB of outstanding image bytes, and 2 MiB per prepared image. Reject an empty or oversized payload before writing; reject a save that exceeds capacity inside the transaction; never evict a pending capture. This store validates payload size, not whether bytes decode into a real image. Read history as metadata with bounded pagination, and fetch image bytes separately by UUID. The byte cap measures logical image data, not database/journal overhead. The existing byte-capacity test is included now; the 10,000-record boundary test will arrive in the next queue-management step.
