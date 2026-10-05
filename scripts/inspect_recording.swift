import Foundation
import AVFoundation
import AppKit

@main
struct InspectRecording {
    static func main() async throws {
        let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let duration = try await asset.load(.duration)
        print("Duration: \(CMTimeGetSeconds(duration)) seconds")
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for argument in CommandLine.arguments.dropFirst(3) {
            let seconds = Double(argument)!
            let result = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            let bitmap = NSBitmapImageRep(cgImage: result.image)
            let path = "\(CommandLine.arguments[2])-\(argument).png"
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
            print("\(path) at \(CMTimeGetSeconds(result.actualTime))s")
        }
    }
}
