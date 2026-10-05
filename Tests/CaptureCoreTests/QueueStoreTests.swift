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
}
