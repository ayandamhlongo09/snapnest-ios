import XCTest
@testable import CaptureCore

private actor ScriptedTransport: UploadTransport {
    var calls = 0
    var failures: Int
    var wrongReceipt = false
    var wrongDigest = false
    var delay: Double
    init(failures: Int = 0, delay: Double = 0) { self.failures = failures; self.delay = delay }
    func setWrongReceipt() { wrongReceipt = true }
    func setWrongDigest() { wrongDigest = true }
    func upload(_ payload: UploadPayload) async throws -> UploadReceipt {
        calls += 1
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        if failures > 0 { failures -= 1; throw CaptureError.server }
        return UploadReceipt(id: wrongReceipt ? UUID() : payload.id, digest: wrongDigest ? "incorrect" : imageDigest(payload.image))
    }
}
final class UploadCoordinatorTests: XCTestCase, @unchecked Sendable {
    private func database() throws -> QueueStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try QueueStore(url: directory.appendingPathComponent("queue.sqlite"))
    }
    func testSuccessUploadsOnceAndRepeatedResumeDoesNotDuplicate() async throws {
        let store = try database(); let transport = ScriptedTransport()
        try await store.save(image: Data([1]), kind: .selfie)
        let coordinator = UploadCoordinator(store: store, transport: transport)
        await coordinator.resume(); await coordinator.waitUntilIdle()
        await coordinator.resume(); await coordinator.waitUntilIdle()
        let item = try await store.items().first; let calls = await transport.calls
        XCTAssertEqual(item?.state, .uploaded); XCTAssertEqual(calls, 1)
    }
    func testAutomaticRetrySucceedsAfterTransientErrors() async throws {
        let store = try database(); let transport = ScriptedTransport(failures: 2)
        try await store.save(image: Data([1]), kind: .selfie)
        let coordinator = UploadCoordinator(store: store, transport: transport, policy: RetryPolicy(baseDelay: 0.01))
        await coordinator.resume(); await coordinator.waitUntilIdle()
        let item = try await store.items().first; let calls = await transport.calls
        XCTAssertEqual(item?.state, .uploaded); XCTAssertEqual(item?.attempts, 3); XCTAssertEqual(calls, 3)
    }
    func testExhaustedRetryBudgetWaitsForManualRetryAndDoesNotBlockLaterItem() async throws {
        let store = try database(); let transport = ScriptedTransport(failures: 3)
        let id = try await store.save(image: Data([1]), kind: .selfie)
        let coordinator = UploadCoordinator(store: store, transport: transport, policy: RetryPolicy(maximumAttempts: 3, baseDelay: 0.001))
        await coordinator.resume(); await coordinator.waitUntilIdle()
        let failed = try await store.items().first
        XCTAssertEqual(failed?.state, .failed); XCTAssertEqual(failed?.attempts, 3)
        try await store.save(image: Data([2]), kind: .document)
        await coordinator.resume(); await coordinator.waitUntilIdle()
        let summary = try await store.summary(); XCTAssertEqual(summary.uploaded, 1)
        try await coordinator.retry(id: id); await coordinator.waitUntilIdle()
        let final = try await store.summary(); XCTAssertEqual(final.uploaded, 2)
    }
    func testWrongReceiptNeverMarksUploaded() async throws {
        let store = try database(); let transport = ScriptedTransport()
        await transport.setWrongReceipt()
        try await store.save(image: Data([1]), kind: .selfie)
        let coordinator = UploadCoordinator(store: store, transport: transport, policy: RetryPolicy(maximumAttempts: 1))
        await coordinator.resume(); await coordinator.waitUntilIdle()
        let item = try await store.items().first; XCTAssertEqual(item?.state, .failed)
        let bytes = try await store.image(id: XCTUnwrap(item?.id)); XCTAssertEqual(bytes, Data([1]))
    }
    func testReceiptForChangedBytesNeverMarksUploaded() async throws {
        let store = try database(); let transport = ScriptedTransport()
        await transport.setWrongDigest()
        let id = try await store.save(image: Data([1]), kind: .selfie)
        let coordinator = UploadCoordinator(store: store, transport: transport, policy: RetryPolicy(maximumAttempts: 1))
        await coordinator.resume(); await coordinator.waitUntilIdle()
        let item = try await store.items().first; let bytes = try await store.image(id: id)
        XCTAssertEqual(item?.state, .failed); XCTAssertEqual(bytes, Data([1]))
    }
    func testRepeatedNewCapturesAndConcurrentResumeDoNotStrandOrDuplicateItems() async throws {
        let store = try database(); let transport = ScriptedTransport(delay: 0.001)
        let coordinator = UploadCoordinator(store: store, transport: transport)
        for _ in 0..<25 {
            try await store.save(image: Data([1]), kind: .selfie)
            await coordinator.resume()
            // Frequent empty-queue resumes exercise worker wake requests as well.
            await coordinator.resume()
        }
        await coordinator.waitUntilIdle()
        let summary = try await store.summary(); let calls = await transport.calls
        XCTAssertEqual(summary.uploaded, 25); XCTAssertEqual(calls, 25)
    }
    func testBackgroundPauseCancelsRequestAndForegroundResumesSameID() async throws {
        let store = try database(); let transport = ScriptedTransport(delay: 0.2)
        let id = try await store.save(image: Data([1]), kind: .selfie)
        let coordinator = UploadCoordinator(store: store, transport: transport)
        await coordinator.resume()
        // Wait for the observable transport boundary rather than guessing when a task was scheduled.
        for _ in 0..<100 { if await transport.calls > 0 { break }; try await Task.sleep(for: .milliseconds(5)) }
        await coordinator.pause()
        let interrupted = try await store.items().first
        XCTAssertEqual(interrupted?.state, .pending); XCTAssertEqual(interrupted?.id, id)
        await coordinator.resume(); await coordinator.waitUntilIdle()
        let sent = try await store.items().first; XCTAssertEqual(sent?.state, .uploaded); XCTAssertEqual(sent?.id, id)
    }
    func testLostConfirmationRetriesWithoutAnotherEndpointRecord() async throws {
        let store = try database(); let receipts = try database(); let endpoint = MockEndpoint(receipts: receipts)
        var settings = FailureSettings(); settings.loseConfirmation = true
        await endpoint.configure(settings)
        let id = try await store.save(image: Data([1]), kind: .selfie)
        let coordinator = UploadCoordinator(store: store, transport: endpoint, policy: RetryPolicy(maximumAttempts: 1))
        await coordinator.resume(); await coordinator.waitUntilIdle()
        let uncertain = try await store.items().first; let accepted = try await endpoint.count()
        XCTAssertEqual(uncertain?.state, .failed); XCTAssertEqual(accepted, 1)
        await endpoint.configure(FailureSettings())
        try await coordinator.retry(id: id); await coordinator.waitUntilIdle()
        let sent = try await store.items().first; let finalCount = try await endpoint.count()
        XCTAssertEqual(sent?.state, .uploaded); XCTAssertEqual(finalCount, 1)
    }
    func testDropAndServerFailureInjectionNeverConfirmSuccess() async throws {
        for mode in 0..<3 {
            let store = try database(); let endpoint = MockEndpoint(receipts: try database())
            var settings = FailureSettings()
            if mode == 0 { settings.dropPercent = 100 }
            if mode == 1 { settings.serverErrors = true }
            if mode == 2 { settings.offline = true }
            await endpoint.configure(settings)
            try await store.save(image: Data([1]), kind: .document)
            let coordinator = UploadCoordinator(store: store, transport: endpoint, policy: RetryPolicy(maximumAttempts: 1))
            await coordinator.resume(); await coordinator.waitUntilIdle()
            let item = try await store.items().first; let count = try await endpoint.count()
            XCTAssertEqual(item?.state, .failed); XCTAssertEqual(count, 0)
        }
    }
}
