import SwiftUI
import AVFoundation
import CaptureCore

struct ContentView: View {
    @ObservedObject var model: CaptureModel
    @State private var kind: CaptureKind = .document
    @State private var capturedKind: CaptureKind = .document
    @State private var library = false
    @State private var camera = false
    @State private var preparing = false
    @State private var unsaved: Data?
    @State private var unsavedKind: CaptureKind = .document
    private var busy: Bool { preparing || model.saving }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Save your photo").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("Your photo stays on this phone until it is sent.").font(.body)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1. Choose your photo").font(.title2.bold())
                        ForEach(CaptureKind.allCases, id: \.self) { option in
                            Button { kind = option } label: {
                                HStack {
                                    Image(systemName: kind == option ? "checkmark.circle.fill" : "circle")
                                    Text(option.title).font(.headline)
                                    Spacer()
                                }.padding().frame(maxWidth: .infinity, minHeight: 52)
                            }.buttonStyle(.bordered).accessibilityAddTraits(kind == option ? .isSelected : [])
                        }
                        Text("2. Take or choose a photo").font(.title2.bold())
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { Task { await openCamera() } } label: {
                                Label("Take photo", systemImage: "camera.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(.borderedProminent).disabled(!model.ready || busy || unsaved != nil)
                        }
                        Button { capturedKind = kind; library = true } label: {
                            Label("Choose photo", systemImage: "photo").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.borderedProminent).disabled(!model.ready || busy || unsaved != nil)
                        if busy { ProgressView("Saving photo…").accessibilityLabel("Saving photo. Please wait.") }
                        if let data = unsaved {
                            Text("Photo has not been saved yet. Keep this screen open and try again.").font(.headline)
                            Button("Save photo again") { Task { await persist(data, kind: unsavedKind) } }
                                .buttonStyle(.borderedProminent).disabled(busy)
                        }
                    }.disabled(busy)
                    if let message = model.message {
                        Label(message, systemImage: "info.circle").font(.headline)
                            .accessibilityIdentifier("captureMessage")
                    }
                    if !model.ready && model.message != nil {
                        Button("Try again") { Task { await model.start() } }.buttonStyle(.borderedProminent)
                    }
                }.padding(20)
            }
            .navigationTitle("SnapNest").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $camera) {
                ImagePicker(kind: capturedKind, sourceType: .camera) { data in
                    camera = false
                    if let data { Task { await prepareAndSave(data, kind: capturedKind) } }
                }.ignoresSafeArea()
            }
            .sheet(isPresented: $library) {
                ImagePicker(kind: capturedKind, sourceType: .photoLibrary) { data in
                    library = false
                    if let data { Task { await prepareAndSave(data, kind: capturedKind) } }
                }.ignoresSafeArea()
            }
        }.tint(Color(red: 0.05, green: 0.28, blue: 0.58))
    }
    private func openCamera() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var allowed = status == .authorized
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        if allowed { capturedKind = kind; camera = true }
        else { model.message = "Allow camera access in Settings, or choose a photo." }
    }
    private func prepareAndSave(_ data: Data, kind: CaptureKind) async {
        preparing = true
        let background = UIApplication.shared.beginBackgroundTask(withName: "Save capture", expirationHandler: nil)
        defer {
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
        do {
            let processed = try await ImageProcessor.shared.prepare(data)
            preparing = false
            await persist(processed, kind: kind)
        } catch { model.message = error.localizedDescription; preparing = false }
    }
    private func persist(_ data: Data, kind: CaptureKind) async {
        unsaved = data; unsavedKind = kind
        if await model.save(data, kind: kind) { unsaved = nil }
    }
}
