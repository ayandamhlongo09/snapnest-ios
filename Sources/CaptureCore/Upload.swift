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
