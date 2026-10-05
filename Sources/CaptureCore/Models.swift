import Foundation

public enum CaptureKind: String, Codable, Sendable, CaseIterable {
    case selfie, document
    public var title: String { self == .selfie ? "Selfie" : "Identity document" }
}
public enum UploadState: String, Codable, Sendable { case pending, uploading, uploaded, failed }
public struct CaptureItem: Identifiable, Sendable {
    public let id: UUID
    public let kind: CaptureKind
    public let createdAt: Date
    public let state: UploadState
    public let attempts: Int
    public let nextAttempt: Date
    public let message: String?
    public let byteCount: Int
}
public struct QueueSummary: Sendable {
    public let total: Int
    public let waiting: Int
    public let uploaded: Int
    public let bytes: Int
}
public struct UploadPayload: Sendable {
    public let id: UUID
    public let kind: CaptureKind
    public let image: Data
}
public struct UploadReceipt: Codable, Sendable {
    public let id: UUID
    public let digest: String
    public init(id: UUID, digest: String) { self.id = id; self.digest = digest }
}
public enum CaptureError: Error, LocalizedError, Sendable {
    case database(String), full, invalidImage, receiptMismatch, collision, server, connection, uncertain
    public var errorDescription: String? {
        switch self {
        case .database: "Phone storage could not be accessed. Please try again."
        case .full: "Storage is full. Send the waiting photos before taking more."
        case .invalidImage: "This photo could not be used. Choose another photo."
        case .receiptMismatch, .collision: "We could not confirm this photo. Please retry."
        case .server: "The service is busy. Your photo is saved."
        case .connection: "The connection was interrupted. Your photo is saved."
        case .uncertain: "Confirmation was interrupted. Your photo is saved."
        }
    }
}

public struct RetryPolicy: Sendable {
    public let maximumAttempts: Int
    public let baseDelay: TimeInterval
    public init(maximumAttempts: Int = 5, baseDelay: TimeInterval = 2) {
        self.maximumAttempts = maximumAttempts; self.baseDelay = baseDelay
    }
    public func delay(after attempt: Int) -> TimeInterval {
        min(60, baseDelay * pow(2, Double(max(0, min(attempt - 1, 10)))))
    }
}
