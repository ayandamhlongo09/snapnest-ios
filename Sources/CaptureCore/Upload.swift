import Foundation
import CryptoKit

public func imageDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
public protocol UploadTransport: Sendable {
    func upload(_ payload: UploadPayload) async throws -> UploadReceipt
}
public struct FailureSettings: Sendable {
    public var offline = false
    public var dropPercent = 0
    public var latencySeconds: Double = 0
    public var serverErrors = false
    public var loseConfirmation = false
    public init() {}
}
/// An in-app endpoint, with a separate persistent receipt database. No network/auth/biometrics.
public actor MockEndpoint: UploadTransport {
    private let receipts: QueueStore
    private var settings = FailureSettings()
    public init(receipts: QueueStore) { self.receipts = receipts }
    public func configure(_ settings: FailureSettings) { self.settings = settings }
    public func count() async throws -> Int { try await receipts.receiptCount() }
    public func upload(_ payload: UploadPayload) async throws -> UploadReceipt {
        let scenario = settings
        if scenario.latencySeconds > 0 { try await Task.sleep(for: .seconds(scenario.latencySeconds)) }
        try Task.checkCancellation()
        if scenario.offline || Int.random(in: 0..<100) < scenario.dropPercent { throw CaptureError.connection }
        if scenario.serverErrors { throw CaptureError.server }
        let result = try await receipts.accept(id: payload.id, digest: imageDigest(payload.image))
        if scenario.loseConfirmation { throw CaptureError.uncertain }
        return result
    }
}

/// Serial worker; actor isolation protects coordination, SQLite protects persistence.
public actor UploadCoordinator {
    private let store: QueueStore
    private let transport: any UploadTransport
    private let policy: RetryPolicy
    private var worker: Task<Void, Never>?
    private var enabled = false
    public private(set) var lastError: String?
    private var generation = 0
    private var needsAnotherPass = false
    private let changed: @Sendable () async -> Void
    public init(store: QueueStore, transport: any UploadTransport, policy: RetryPolicy = RetryPolicy(),
                changed: @escaping @Sendable () async -> Void = {}) {
        self.store = store; self.transport = transport; self.policy = policy; self.changed = changed
    }
    public func resume() {
        enabled = true
        lastError = nil
        guard worker == nil else { needsAnotherPass = true; return }
        needsAnotherPass = false
        generation += 1
        let token = generation
        worker = Task { await self.drain(token: token) }
    }
    public func pause() async {
        enabled = false
        let old = worker
        old?.cancel()
        // Wait until the old claim has been resolved before allowing recovery/new work.
        await old?.value
    }
    public func retry(id: UUID) async throws {
        try await store.retry(id: id)
        // Wake backoff sleep; wait for cancellation cleanup before starting another worker.
        let wasEnabled = enabled
        await pause()
        await changed()
        if wasEnabled { resume() }
    }
    private func drain(token: Int) async {
        defer {
            if generation == token {
                worker = nil
                if enabled && needsAnotherPass { resume() }
            }
        }
        do {
            while enabled && !Task.isCancelled {
                guard let payload = try await store.claim(now: Date(), maximumAttempts: policy.maximumAttempts) else {
                    guard let due = try await store.nextDue(maximumAttempts: policy.maximumAttempts) else { return }
                    try await Task.sleep(for: .seconds(max(0.05, due.timeIntervalSinceNow)))
                    continue
                }
                await changed()
                do {
                    let receipt = try await transport.upload(payload)
                    guard receipt.id == payload.id, receipt.digest == imageDigest(payload.image) else { throw CaptureError.receiptMismatch }
                    // Honour confirmed acceptance even when pause arrived during endpoint commit.
                    try await store.markUploaded(id: payload.id)
                } catch is CancellationError {
                    try await store.recoverInterrupted()
                    await changed(); return
                } catch {
                    try await store.markFailed(id: payload.id, message: error.localizedDescription, now: Date(), policy: policy)
                }
                await changed()
            }
        } catch is CancellationError {
            // Sleep cancellation has no in-flight claim.
        } catch {
            // Disk errors leave the last durable state intact; foreground/relaunch retries recovery.
            lastError = error.localizedDescription
            await changed()
        }
    }
    /// Test/reviewer hook: waits for the current worker, including its automatic retries.
    public func waitUntilIdle() async {
        while let current = worker { await current.value }
    }
}
