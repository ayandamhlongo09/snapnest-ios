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
Define four states: `pending`, `uploading`, `uploaded`, and `failed`. Capture metadata includes attempts, the next eligible attempt time, and an explanatory message. `QueueSummary` provides counts and outstanding image bytes for the interface. SQLite queue operations now persist these transitions and recover interrupted uploading rows. The delivery worker now coordinates those operations.

## Delivery confirmation

**Concept**
A response must identify which capture was accepted and which image bytes it refers to. A retry after a lost response can otherwise create a duplicate.

**Decision**
Represent confirmation with an `UploadReceipt` containing the capture UUID and image digest. The worker validates both before marking a capture uploaded, and the mock receiver deduplicates repeated requests. The mock endpoint now calculates SHA-256 digests and records receipts. The coordinator now uses this transport; no live HTTP request is made.

## Retry policy

**Concept**
Repeated immediate attempts can overload an unavailable service. Automatic attempts also need a limit so persistent failures remain visible and actionable.

**Decision**
Use the existing policy of five automatic attempts, starting with a two-second retry delay and doubling subsequent delays. The delay function caps at 60 seconds; the five-attempt budget normally uses delays of 2, 4, 8, and 16 seconds. Manual retry renews the failed capture’s budget and wakes the coordinator. The existing unit test verifies exponential delay and the cap. Deterministic delays keep this prototype simple; fleet-wide retry jitter is not implemented.

## Durable photo storage

**Concept**
A captured photo must survive an app restart before delivery is attempted. “Saved” means its bytes and queue metadata have committed to disk. A photo still held in memory has not crossed that boundary.

**Decision**
Store image bytes, UUID, capture type, timestamp, and pending state together in one SQLite transaction. `BEGIN IMMEDIATE` starts the write transaction; the capacity check and insert happen inside it; `COMMIT` completes the save. A failure rolls the transaction back. This avoids coordinating separate image files with metadata. A duplicate ID is rejected without overwriting the original capture. The existing tests verify reopened bytes/state and rollback. Process-kill validation will be introduced in its planned later step.

The storage operation follows this path; camera/UI integration will call it in a later step.

```mermaid
flowchart TD
    A[Image bytes and capture metadata] --> B{Valid payload size?}
    B -->|No| R[Reject save]
    B -->|Yes| C[Begin SQLite transaction]
    C --> D{Within queue capacity?}
    D -->|No| E[Roll back and report full]
    D -->|Yes| F[Insert image and pending metadata together]
    F --> G{Insert and commit succeed?}
    G -->|No| H[Roll back and report failure]
    G -->|Yes| I[Return saved capture UUID]
```

## SQLite ownership and durability

**Concept**
Concurrent operations must not interleave halfway through a transaction, and the database connection must remain valid until its owner finishes using it.

**Decision**
Give one `QueueStore` actor ownership of one SQLite connection. Database operations are synchronous within the actor, so a transaction has no suspension point where another actor call can interleave. A private connection holder closes the handle when ownership ends; its narrow `@unchecked Sendable` declaration relies on this confinement. Use SQLite's DELETE rollback journal and FULL synchronization to prioritise committed-save durability over write throughput. These mechanisms do not protect against app uninstall, device loss, or arbitrary filesystem corruption.

## Storage bounds and reads

**Concept**
Image storage can consume disk space quickly. Rejecting a new capture must preserve the photos already saved. History reads should avoid loading all image bytes into memory.

**Decision**
Reuse the existing save-time limits: 10,000 total capture records, 512 MiB of outstanding image bytes, and 2 MiB per prepared image. Reject an empty or oversized payload before writing; reject a save that exceeds capacity inside the transaction; never evict a pending capture. This store validates payload size, not whether bytes decode into a real image. Read history as metadata with bounded pagination, and fetch image bytes separately by UUID. The byte cap measures logical image data, not database/journal overhead. The existing byte-capacity test is included now; the 10,000-record boundary and final-page pagination test are now included.

## Exclusive upload claims

**Concept**
Two overlapping requests must not select the same waiting capture. An attempt must be recorded before the image is handed to the uploader.

**Decision**
Within one SQLite transaction, select the oldest eligible pending or failed capture, change it to uploading, and increment its attempts. Return its UUID and image bytes only after commit. An uploading row is not eligible for another claim. The existing concurrent-claim test verifies that only one caller receives the payload. The coordinator also limits delivery to a single worker.

## Retry timing and manual retry

**Concept**
Retry timing must survive process restarts. A persistent failure should stop using automatic attempts while allowing the user to try again.

**Decision**
Persist each failure message and next-attempt timestamp. Claims require both a due timestamp and an attempt count below the supplied budget. Manual retry resets a failed capture to pending, clears its timing/message, and renews its budget while preserving its UUID and image. The existing test verifies an early claim is refused, the two-second initial delay is persisted, and manual retry returns the original image and ID. The coordinator now schedules automatic attempts using these persisted due times.

## Interrupted-upload recovery

**Concept**
After interruption, an uploading row has no locally confirmed outcome. The receiver might already have accepted it, even though the client did not record confirmation.

**Decision**
Recover uploading rows to pending, clear their timing/message, and refund the interrupted attempt. Reuse the original UUID so the later idempotent receiver can recognise a repeated request. Do not change confirmed uploaded rows. The existing recovery test reopens the database, reclaims the same ID, and verifies confirmed rows remain uploaded. Lifecycle integration and remote deduplication are introduced later.

## Confirmed-upload cleanup

**Concept**
Accepted photos no longer need their local image bytes, but removing sent history must never delete waiting photos. The database file can retain allocated pages after logical deletion.

**Decision**
For an uploading row, the storage operation marks it uploaded and releases its image BLOB and logical byte count. The worker calls this only after validating a receipt; the store does not validate a receipt itself. Sent-history cleanup deletes only uploaded rows and runs VACUUM to reclaim database space, requiring temporary disk headroom. The existing test verifies pending IDs and bytes remain intact. The 10,000-record policy counts sent metadata until it is cleared.

## Idempotent mock receiver

**Concept**
A receiver can accept an image even when its response never reaches the client. The client must be able to repeat the same request without creating a second accepted capture.

**Decision**
Use the existing in-app `MockEndpoint` behind an `UploadTransport` protocol. Calculate a SHA-256 digest of the delivered bytes and record the UUID/digest in SQLite. An atomic receipt transaction returns the same receipt for a repeated UUID and digest, and rejects the same UUID with different bytes. Receipts survive reopening; the existing test verifies persistence, deduplication, and collision rejection. This represents receiver acceptance in a permitted mock, not transmission to a real backend. When app integration arrives, receipts will use a database separate from the client's queue.

The diagram shows receipt handling inside the mock endpoint. The coordinator calls this transport; app UI integration is introduced later.

```mermaid
sequenceDiagram
    participant Caller
    participant Mock as Mock endpoint
    participant DB as SQLite receipt store
    Caller->>Mock: Upload UUID and image bytes
    Mock->>Mock: Calculate SHA-256 digest
    Mock->>DB: Accept UUID and digest in a transaction
    alt UUID not yet accepted
        DB->>DB: Insert and commit receipt
        DB-->>Mock: New receipt
    else Same UUID and digest
        DB-->>Mock: Original receipt
    else Same UUID with different digest
        DB-->>Mock: Reject conflicting bytes
    end
    alt Accepted but response-loss simulation enabled
        Mock-->>Caller: Confirmation interrupted
    else Accepted and confirmation available
        Mock-->>Caller: Receipt containing UUID and digest
    else Conflicting bytes rejected
        Mock-->>Caller: Collision error
    end
```

## Failure simulation at the transport boundary

**Concept**
Testing delivery needs controlled failures, including the ambiguous case where acceptance succeeds but confirmation is lost.

**Decision**
Reuse the endpoint's existing configurable offline mode, request-drop percentage, latency, server errors, and response loss after acceptance. Each request snapshots its settings; task cancellation is checked before acceptance. Response-loss simulation commits the receipt and then throws, allowing the worker tests to verify safe retries. These controls are not connected to a screen yet, and the existing coordinator tests now exercise the failure scenarios.

## Receipt retention

**Concept**
Deleting the client's sent history must not make a repeated request appear new to the receiver.

**Decision**
Keep mock receipts independently of capture-history cleanup and retain them indefinitely in this prototype. The receipt database stores IDs and digests, not image bytes. Its growth is an explicit limitation separate from the bounded image queue; a production receiver would need a retention and duplicate-window contract.

## Serial upload coordination

**Concept**
Swift actors protect their state, but an actor can handle another call while a method is suspended at `await`. Actor isolation alone does not ensure that an entire upload request runs alone. A newly saved capture must also not be stranded as an earlier worker exits.

**Decision**
Reuse the existing `UploadCoordinator` actor with one owned worker task. Repeated resume calls request another pass instead of creating overlapping workers; a generation token protects worker cleanup. Claim one eligible capture at a time, notify observers, upload its saved bytes, and resolve the durable state before moving on. The existing tests verify repeated resumes and 25 successive captures do not strand items or duplicate transport calls. This predictable memory/concurrency policy trades throughput for simplicity.

## Confirmed delivery and whole-image retries

**Concept**
An upload attempt is not proof of delivery. A matching receipt is needed before local image bytes can be released. If confirmation is lost after acceptance, the client cannot tell whether the receiver committed.

**Decision**
Validate both the receipt UUID and SHA-256 digest against the payload. Only then mark the capture uploaded. Persist failures and their next retry time; wait for the earliest eligible attempt when none is due. Retry the entire saved image with the same UUID, relying on the mock receiver's idempotency. After five unsuccessful attempts, keep the image failed until manual retry resets its budget. Other eligible captures can still proceed. The existing tests cover transient success, exhaustion, progress beyond failed items, incorrect IDs/digests, and lost confirmation with one unique acceptance.

```mermaid
flowchart TD
    A[Resume delivery] --> B{Worker already exists?}
    B -->|Yes| C[Request another pass]
    B -->|No| D[Start one worker]
    D --> E{Eligible capture available?}
    E -->|Yes| F[Claim and persist uploading state]
    E -->|No| G{Future retry due?}
    G -->|Yes| H[Wait until retry time]
    H --> E
    G -->|No| I[Finish worker and honour wake request]
    F --> J[Send saved bytes with original UUID]
    J --> K{Matching UUID and digest receipt?}
    K -->|Yes| L[Mark uploaded and release local image]
    K -->|No or request failure| M[Persist failure and next retry time]
    L --> E
    M --> E
```

The diagram covers normal scheduling and outcomes. Failed captures at the attempt limit remain saved and ineligible until manual retry; cancellation follows the recovery path below.

## Pause, cancellation, and wake-up

**Concept**
Pausing while a request is active must leave a recoverable durable state. A confirmed response arriving during cancellation must not be discarded.

**Decision**
Pause disables and cancels the worker, then awaits its completion before recovery or new work. Request cancellation recovers unconfirmed uploading rows to pending. A matching receipt received despite cancellation is still honoured as confirmed success. Manual retry pauses the current worker to interrupt backoff, publishes the changed state, then resumes if delivery was enabled. Storage-worker errors are exposed through `lastError` while preserving the last durable state. The existing pause/resume test verifies the same capture ID is eventually sent. Foreground/connectivity integration is still a later app step.
