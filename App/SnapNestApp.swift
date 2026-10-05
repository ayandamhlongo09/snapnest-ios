import SwiftUI

@main
struct SnapNestApp: App {
    @StateObject private var model = CaptureModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task { await model.start() }
                .onChange(of: phase) { _, phase in
                    Task { await model.setActive(phase == .active) }
                }
        }
    }
}
