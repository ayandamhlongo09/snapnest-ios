import SwiftUI
import UIKit
import ImageIO
import CaptureCore

actor ImageProcessor {
    static let shared = ImageProcessor()
    func prepare(_ data: Data) throws -> Data {
        guard data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CaptureError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { throw CaptureError.invalidImage }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= QueueStore.maximumImageBytes else { throw CaptureError.invalidImage }
        return output as Data
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let kind: CaptureKind
    let sourceType: UIImagePickerController.SourceType
    let completed: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        if sourceType == .camera, kind == .selfie, UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completed: (Data?) -> Void
        init(completed: @escaping (Data?) -> Void) { self.completed = completed }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completed(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) else { completed(Data()); return }
            completed(data)
        }
    }
}
