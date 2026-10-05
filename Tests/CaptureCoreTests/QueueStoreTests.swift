import XCTest
@testable import CaptureCore

final class QueueStoreTests: XCTestCase, @unchecked Sendable {
    private func database(itemLimit: Int = 10_000, byteLimit: Int = 512 * 1024 * 1024) throws -> (QueueStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("queue.sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (try QueueStore(url: url, itemLimit: itemLimit, byteLimit: byteLimit), url)
    }
    func testSaveCommitsImageAndPendingStateTogetherAcrossReopen() async throws {
        let (store, url) = try database()
        let image = Data([1,2,3,4])
        let id = try await store.save(image: image, kind: .document)
        let reopened = try QueueStore(url: url)
        let items = try await reopened.items()
        let stored = try await reopened.image(id: id)
        XCTAssertEqual(items.count, 1); XCTAssertEqual(items.first?.id, id)
        XCTAssertEqual(items.first?.state, .pending); XCTAssertEqual(items.first?.kind, .document)
        XCTAssertEqual(stored, image)
        let integrity = try await reopened.integrityCheck(); XCTAssertEqual(integrity, "ok")
    }
    func testDuplicateSaveRollsBackWithoutOverwritingOriginalBytes() async throws {
        let (store, _) = try database()
        let id = try await store.save(image: Data([1]), kind: .selfie)
        do { try await store.save(image: Data([2]), kind: .document, id: id); XCTFail("duplicate accepted") } catch {}
        let stored = try await store.image(id: id); let count = try await store.summary().total
        XCTAssertEqual(stored, Data([1])); XCTAssertEqual(count, 1)
    }
    func testInvalidAndOversizedCapturesNeverEnterQueue() async throws {
        let (store, _) = try database()
        for image in [Data(), Data(repeating: 1, count: QueueStore.maximumImageBytes + 1)] {
            do { try await store.save(image: image, kind: .selfie); XCTFail("invalid accepted") }
            catch CaptureError.invalidImage {} catch { XCTFail("wrong error \(error)") }
        }
        let count = try await store.summary().total; XCTAssertEqual(count, 0)
    }
    func testByteCapacityRejectsNewCaptureAndPreservesExisting() async throws {
        let (store, _) = try database(byteLimit: 3)
        let id = try await store.save(image: Data([1,2,3]), kind: .selfie)
        do { try await store.save(image: Data([4]), kind: .selfie); XCTFail("capacity exceeded") }
        catch CaptureError.full {}
        let stored = try await store.image(id: id); XCTAssertEqual(stored, Data([1,2,3]))
    }
    func testTenThousandRecordsAreBoundedAndPagedWithoutDroppingPending() async throws {
        let (store, _) = try database()
        for _ in 0..<10_000 { try await store.save(image: Data([1]), kind: .document) }
        do { try await store.save(image: Data([2]), kind: .selfie); XCTFail("10001st accepted") }
        catch CaptureError.full {}
        let summary = try await store.summary(); let page = try await store.items(limit: 50, offset: 9950)
        XCTAssertEqual(summary.total, 10_000); XCTAssertEqual(summary.waiting, 10_000)
        XCTAssertEqual(page.count, 50)
        let integrity = try await store.integrityCheck(); XCTAssertEqual(integrity, "ok")
    }
    func testRecoveryReclaimsUploadingButLeavesUploadedAndFailedAlone() async throws {
        let (store, url) = try database()
        let id = try await store.save(image: Data([1]), kind: .selfie)
        _ = try await store.claim(now: Date(), maximumAttempts: 5)
        let reopened = try QueueStore(url: url)
        try await reopened.recoverInterrupted()
        let recovered = try await reopened.items().first
        XCTAssertEqual(recovered?.state, .pending); XCTAssertEqual(recovered?.attempts, 0)
        let payload = try await reopened.claim(now: Date(), maximumAttempts: 5)
        XCTAssertEqual(payload?.id, id)
        try await reopened.markUploaded(id: id); try await reopened.recoverInterrupted()
        let sent = try await reopened.items().first
        XCTAssertEqual(sent?.state, .uploaded)
        let next = try await reopened.claim(now: Date(), maximumAttempts: 5); XCTAssertNil(next)
    }
    func testClaimIsExclusiveAndAttemptsArePersisted() async throws {
        let (store, _) = try database()
        try await store.save(image: Data([1]), kind: .selfie)
        async let a = store.claim(now: Date(), maximumAttempts: 5)
        async let b = store.claim(now: Date(), maximumAttempts: 5)
        let results = try await [a, b]
        XCTAssertEqual(results.compactMap { $0 }.count, 1)
        let item = try await store.items().first
        XCTAssertEqual(item?.state, .uploading); XCTAssertEqual(item?.attempts, 1)
    }
    func testBackoffDueTimeAndManualRetryPreserveSameImageID() async throws {
        let (store, _) = try database()
        let id = try await store.save(image: Data([1]), kind: .selfie)
        let now = Date()
        _ = try await store.claim(now: now, maximumAttempts: 5)
        try await store.markFailed(id: id, message: "busy", now: now, policy: RetryPolicy())
        let early = try await store.claim(now: now.addingTimeInterval(1), maximumAttempts: 5)
        XCTAssertNil(early)
        let due = try await store.nextDue(maximumAttempts: 5)
        XCTAssertEqual(due?.timeIntervalSince1970 ?? 0, now.addingTimeInterval(2).timeIntervalSince1970, accuracy: 0.001)
        try await store.retry(id: id)
        let retry = try await store.claim(now: now, maximumAttempts: 5)
        XCTAssertEqual(retry?.id, id); XCTAssertEqual(retry?.image, Data([1]))
    }
    func testConfirmedUploadReleasesBytesAndClearingHistoryKeepsPending() async throws {
        let (store, _) = try database(itemLimit: 2, byteLimit: 4)
        let sentID = try await store.save(image: Data([1,2]), kind: .selfie)
        _ = try await store.claim(now: Date(), maximumAttempts: 5)
        try await store.markUploaded(id: sentID)
        let pendingID = try await store.save(image: Data([3,4]), kind: .document)
        try await store.clearUploadedHistory()
        let items = try await store.items(); let summary = try await store.summary()
        XCTAssertEqual(items.map(\.id), [pendingID]); XCTAssertEqual(summary.bytes, 2)
    }
}
