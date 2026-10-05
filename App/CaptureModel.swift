import SwiftUI
import Network
import CaptureCore

@MainActor
final class CaptureModel: ObservableObject {
    @Published var items: [CaptureItem] = []
    @Published var summary: QueueSummary?
    @Published var message: String?
    @Published var saving = false
    @Published var ready = false
    @Published var connected = true
    @Published var offline = false
    @Published var dropPercent = 0.0
    @Published var latency = 1.0
    @Published var serverErrors = false
    @Published var loseConfirmation = false
    @Published var accepted = 0
    @Published var page = 0
    private var store: QueueStore?
    private var endpoint: MockEndpoint?
    private var coordinator: UploadCoordinator?
    private var monitor: NWPathMonitor?
    private var connectivityGeneration = 0
    private var active = true
    private var started = false
    private var refreshGeneration = 0
    private var previousDemoOffline = false

    func start() async {
        guard !started else { return }
        started = true
        do {
            var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true).appendingPathComponent("SnapNest", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            let store = try QueueStore(url: directory.appendingPathComponent("queue.sqlite"))
            let receipts = try QueueStore(url: directory.appendingPathComponent("mock-receipts.sqlite"))
            self.store = store
            let endpoint = MockEndpoint(receipts: receipts); self.endpoint = endpoint
            coordinator = UploadCoordinator(store: store, transport: endpoint, changed: { [weak self] in await self?.refresh() })
            try await store.recoverInterrupted()
            ready = true
            restartConnectivityMonitoring()
            await refresh(); await updateDelivery()
        } catch { message = error.localizedDescription; started = false }
    }
    func setActive(_ value: Bool) async {
        active = value
        if value { restartConnectivityMonitoring() }
        if value, let store {
            // Pause first: recovery must never steal a live worker's uploading row.
            await coordinator?.pause()
            do { try await store.recoverInterrupted() } catch { message = error.localizedDescription }
            await refresh()
        }
        await updateDelivery()
    }
    private func restartConnectivityMonitoring() {
        connectivityGeneration += 1
        let generation = connectivityGeneration
        monitor?.cancel()
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.connectivityGeneration == generation else { return }
                self.connected = online
                await self.updateDelivery()
            }
        }
        monitor.start(queue: DispatchQueue(label: "SnapNest.connectivity"))
    }
    func checkConnection() {
        restartConnectivityMonitoring()
    }
    func updateDelivery() async {
        let leavingDemoOffline = previousDemoOffline && !offline
        previousDemoOffline = offline
        if leavingDemoOffline { restartConnectivityMonitoring() }
        var settings = FailureSettings()
        settings.offline = offline; settings.dropPercent = Int(dropPercent)
        settings.latencySeconds = latency; settings.serverErrors = serverErrors
        settings.loseConfirmation = loseConfirmation
        await endpoint?.configure(settings)
        if active && connected && !offline { await coordinator?.resume() }
        else { await coordinator?.pause() }
        await refresh()
    }
    func save(_ data: Data, kind: CaptureKind) async -> Bool {
        guard !saving, let store else { return false }
        saving = true; defer { saving = false }
        do {
            try await store.save(image: data, kind: kind)
            page = 0; message = "Photo saved on this phone."
            await refresh(); await updateDelivery()
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func refresh() async {
        guard let store else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let requestedPage = page
        do {
            let latestSummary = try await store.summary()
            let latestItems = try await store.items(limit: 50, offset: requestedPage * 50)
            let latestAccepted = try await endpoint?.count() ?? 0
            let issue = await coordinator?.lastError
            // Publish a complete refresh together. Older page/state reads must not overwrite newer ones.
            guard generation == refreshGeneration else { return }
            summary = latestSummary; items = latestItems; accepted = latestAccepted
            if let issue { message = issue }
        } catch {
            if generation == refreshGeneration { message = error.localizedDescription }
        }
    }
    func retry(_ id: UUID) async {
        do { try await coordinator?.retry(id: id); await updateDelivery() }
        catch { message = error.localizedDescription }
    }
    func clearSent() async {
        do { try await store?.clearUploadedHistory(); page = 0; await refresh() }
        catch { message = error.localizedDescription }
    }
    func movePage(_ change: Int) async { page = max(0, page + change); await refresh() }
}
