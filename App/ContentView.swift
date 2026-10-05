import SwiftUI
import AVFoundation
import CaptureCore

struct ContentView: View {
    @ObservedObject var model: CaptureModel
    @State private var kind: CaptureKind = .document
    @State private var capturedKind: CaptureKind = .document
    @State private var library = false
    @State private var camera = false
    @State private var controls = false
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
                    if !model.connected || model.offline {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(model.offline ? "Demo offline mode is on. Turn it off in Demo controls to send photos." : "No connection. Photos will send when you are back online.", systemImage: "wifi.slash")
                                .font(.headline)
                            if !model.offline {
                                Button("Check connection") { model.checkConnection() }
                                    .buttonStyle(.bordered).accessibilityIdentifier("checkConnection")
                            }
                        }.padding().background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }
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
                    Divider()
                    Text("Your photos").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    if let summary = model.summary {
                        Text("\(summary.waiting) waiting · \(summary.uploaded) sent").font(.headline)
                        if summary.uploaded > 0 {
                            Button("Remove sent photos from this list") { Task { await model.clearSent() } }
                                .buttonStyle(.bordered)
                        }
                    }
                    if model.items.isEmpty { Text("Your saved photos will appear here.") }
                    ForEach(model.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.kind.title).font(.headline)
                            Text(item.createdAt, format: .dateTime.day().month().hour().minute()).font(.subheadline)
                            Label(stateTitle(item.state), systemImage: stateIcon(item.state)).font(.headline)
                            if item.state == .failed {
                                Text(item.attempts >= 5 ? "Photo saved. Tap Retry to send it." : "Photo saved. We will try again shortly.")
                                Button("Retry") { Task { await model.retry(item.id) } }
                                    .buttonStyle(.borderedProminent).frame(minHeight: 48)
                            }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if (model.summary?.total ?? 0) > 50 {
                        VStack(spacing: 12) {
                            Text("Page \(model.page + 1)")
                            Button("Previous photos") { Task { await model.movePage(-1) } }.disabled(model.page == 0)
                            Button("More photos") { Task { await model.movePage(1) } }
                                .disabled((model.page + 1) * 50 >= (model.summary?.total ?? 0))
                        }.buttonStyle(.bordered)
                    }
                }.padding(20)
            }
            .navigationTitle("SnapNest").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("SnapNestLogo")
                            .resizable().scaledToFit()
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .accessibilityHidden(true)
                        Text("SnapNest").font(.headline)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                Button { controls = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Demo controls")
            } }
            .sheet(isPresented: $camera) {
                ImagePicker(kind: capturedKind, sourceType: .camera) { data in
                    camera = false
                    if let data { Task { await prepareAndSave(data, kind: capturedKind) } }
                }.ignoresSafeArea()
            }
            .sheet(isPresented: $controls) { DemoControls(model: model) }
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
    private func stateTitle(_ state: UploadState) -> String {
        switch state { case .pending: "Saved · Waiting to send"; case .uploading: "Saved · Sending…"; case .uploaded: "Sent"; case .failed: "Saved · Needs another try" }
    }
    private func stateIcon(_ state: UploadState) -> String {
        switch state { case .pending: "clock"; case .uploading: "arrow.up.circle"; case .uploaded: "checkmark.circle.fill"; case .failed: "exclamationmark.arrow.circlepath" }
    }
}

struct DemoControls: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Break delivery") {
                    Toggle("Go offline", isOn: $model.offline)
                    Toggle("Server errors (503)", isOn: $model.serverErrors)
                    Toggle("Lose response after acceptance", isOn: $model.loseConfirmation)
                    VStack(alignment: .leading) {
                        Text("Drop uploads: \(Int(model.dropPercent))%")
                        Slider(value: $model.dropPercent, in: 0...100, step: 10).accessibilityLabel("Drop upload percentage")
                    }
                    VStack(alignment: .leading) {
                        Text("Delay: \(Int(model.latency)) seconds")
                        Slider(value: $model.latency, in: 0...15, step: 1).accessibilityLabel("Upload delay")
                    }
                    Text("Controls apply to the next request. Offline cancels the current request. Real connectivity changes also pause delivery.")
                }
                Section("Endpoint evidence") {
                    Text("\(model.accepted) unique photos accepted")
                    Text("Repeat requests with the same ID and image return the original receipt. Changed image bytes are rejected.")
                }
                Section("Storage") {
                    Text("Maximum 10,000 records and 512 MiB of waiting photos. Sent image bytes are removed after confirmation.")
                    Button("Clear sent history") { Task { await model.clearSent() } }
                    Text("Waiting photos are kept. Endpoint receipts stay for duplicate checks.")
                }
            }.navigationTitle("Demo controls")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onChange(of: model.offline) { _, _ in Task { await model.updateDelivery() } }
                .onChange(of: model.serverErrors) { _, _ in Task { await model.updateDelivery() } }
                .onChange(of: model.loseConfirmation) { _, _ in Task { await model.updateDelivery() } }
                .onChange(of: model.dropPercent) { _, _ in Task { await model.updateDelivery() } }
                .onChange(of: model.latency) { _, _ in Task { await model.updateDelivery() } }
        }
    }
}
