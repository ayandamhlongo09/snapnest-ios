import Foundation
import AVFoundation

@main
struct TrimRecording {
    static func main() async throws {
        guard CommandLine.arguments.count == 5 else { fatalError("input output start duration") }
        let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let start = Double(CommandLine.arguments[3])!
        let duration = Double(CommandLine.arguments[4])!
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { fatalError("No export session") }
        export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: duration, preferredTimescale: 600))
        try await export.export(to: URL(fileURLWithPath: CommandLine.arguments[2]), as: .mov)
        let result = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[2]))
        let length = try await result.load(.duration)
        print("Exported \(CMTimeGetSeconds(length)) seconds")
    }
}
