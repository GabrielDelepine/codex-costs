import Foundation
import Network
import Observation

// Shared by pricing and release checks. QA flags are local to this app launch.
@MainActor @Observable final class NetworkRequests {
    static let shared = NetworkRequests()
    var simulateOffline: Bool { didSet { if oldValue != simulateOffline { simulationChanged() } } }
    var simulatePacketLoss: Bool { didSet { if oldValue != simulatePacketLoss { simulationChanged() } } }
    private(set) var systemAvailable: Bool?
    var available: Bool? { simulateOffline ? false : (simulatePacketLoss ? true : systemAvailable) }
    var simulationStatus: String {
        if simulateOffline { return "Network test: Offline" }
        return simulatePacketLoss ? "Network test: 100% packet loss" : ""
    }
    @ObservationIgnored var connectionRestored: (() -> Void)?
    private var reportedAvailable: Bool?
    private var revision = 0
    private var requests: [UUID: Task<(Data, URLResponse), Error>] = [:]
    private var monitor: NWPathMonitor?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        simulateOffline = environment["CODEX_COSTS_SIMULATE_OFFLINE"] == "1"
        simulatePacketLoss = environment["CODEX_COSTS_SIMULATE_PACKET_LOSS"] == "1"
        reportedAvailable = available
    }
    private func simulationChanged() {
        revision += 1
        for request in requests.values { request.cancel() }
        reportAvailability()
    }
    private func reportAvailability() {
        guard reportedAvailable != available else { return }
        let restored = reportedAvailable == false && available != false
        reportedAvailable = available
        if restored { connectionRestored?() }
    }
    func updateSystemAvailability(_ available: Bool) {
        systemAvailable = available
        reportAvailability()
    }
    func startMonitoring() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status != .unsatisfied
            Task { @MainActor [weak self] in self?.updateSystemAvailability(available) }
        }
        self.monitor = monitor
        monitor.start(queue: DispatchQueue(label: "CodexCosts.network"))
    }
    func stopMonitoring() { monitor?.cancel(); monitor = nil }

    func data(for request: URLRequest, session: URLSession = .shared) async throws -> (Data, URLResponse) {
        let id = UUID()
        defer { requests[id] = nil }
        while true {
            try Task.checkCancellation()
            if simulateOffline { throw URLError(.notConnectedToInternet) }
            let startedRevision = revision
            let packetLoss = simulatePacketLoss
            let operation = Task {
                if packetLoss {
                    // Exercise the normal timeout path without transmitting a request.
                    try await Task.sleep(for: .seconds(request.timeoutInterval))
                    throw URLError(.timedOut)
                }
                return try await session.data(for: request)
            }
            requests[id] = operation
            do {
                let result = try await withTaskCancellationHandler {
                    try await operation.value
                } onCancel: {
                    operation.cancel()
                }
                try Task.checkCancellation()
                // A toggle may race a completed response. Apply the new simulation first.
                if startedRevision != revision { continue }
                return result
            } catch {
                try Task.checkCancellation()
                if startedRevision != revision { continue }
                throw error
            }
        }
    }
}
