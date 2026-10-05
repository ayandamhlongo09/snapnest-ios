import Foundation
import CaptureCore

@main
struct QueueProbe {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: QueueProbe write|check database-path") }
        let store = try QueueStore(url: URL(fileURLWithPath: CommandLine.arguments[2]))
        if CommandLine.arguments[1] == "write" {
            for _ in 0..<1000 {
                let id = try await store.save(image: Data(repeating: 0x5a, count: 1024 * 1024), kind: .document)
                // A line is emitted ONLY after save returns, hence after COMMIT.
                try FileHandle.standardOutput.write(contentsOf: Data((id.uuidString + "\n").utf8))
            }
        } else {
            let summary = try await store.summary()
            let integrity = try await store.integrityCheck()
            try FileHandle.standardOutput.write(contentsOf: Data("\(integrity) \(summary.total) \(summary.bytes)\n".utf8))
        }
    }
}
