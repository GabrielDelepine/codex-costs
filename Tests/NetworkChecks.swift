import Foundation

final class NetworkStub: URLProtocol {
    static let lock = NSLock()
    private static var count = 0
    private static var hold = false
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func holdRequests(_ value: Bool) { lock.lock(); hold = value; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        let hold = Self.hold
        Self.lock.unlock()
        if hold { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                                                            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("fixture".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct NetworkChecks {
    @MainActor static func expectError(_ code: URLError.Code, _ operation: () async throws -> (Data, URLResponse)) async {
        do { _ = try await operation(); preconditionFailure("Expected \(code)") }
        catch { precondition((error as? URLError)?.code == code, "Unexpected error: \(error)") }
    }
    @MainActor static func main() async throws {
        let network = NetworkRequests(environment: [:])
        precondition(!network.simulateOffline && !network.simulatePacketLoss && network.available == nil)
        let startup = NetworkRequests(environment: ["CODEX_COSTS_SIMULATE_OFFLINE": "1", "CODEX_COSTS_SIMULATE_PACKET_LOSS": "1"])
        precondition(startup.simulateOffline && startup.simulatePacketLoss && startup.available == false)
        startup.simulateOffline = false
        precondition(startup.available == true)
        precondition(!NetworkRequests(environment: [:]).simulateOffline)
        var recoveries = 0
        network.connectionRestored = { recoveries += 1 }
        network.updateSystemAvailability(true)
        network.simulateOffline = true
        network.updateSystemAvailability(false)
        network.updateSystemAvailability(true)
        precondition(network.available == false && recoveries == 0)
        network.simulateOffline = false
        precondition(network.available == true && recoveries == 1)
        network.simulatePacketLoss = true
        network.simulatePacketLoss = false
        precondition(recoveries == 1) // Packet-loss recovery must not fake a path change.
        network.simulateOffline = true
        network.updateSystemAvailability(false)
        network.simulateOffline = false
        precondition(network.available == false && recoveries == 1)
        network.updateSystemAvailability(true)
        precondition(recoveries == 2)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://fixture.invalid/prices")!)
        request.timeoutInterval = 0.08
        let normal = try await network.data(for: request, session: session)
        precondition(normal.0 == Data("fixture".utf8) && NetworkStub.requestCount == 1)
        network.simulateOffline = true
        network.simulatePacketLoss = true
        await expectError(.notConnectedToInternet) { try await network.data(for: request, session: session) }
        precondition(NetworkStub.requestCount == 1)
        network.simulateOffline = false
        let clock = ContinuousClock()
        let started = clock.now
        await expectError(.timedOut) { try await network.data(for: request, session: session) }
        precondition(started.duration(to: clock.now) >= .milliseconds(70) && NetworkStub.requestCount == 1)

        request.timeoutInterval = 10
        let waiting = Task { try await network.data(for: request, session: session) }
        try await Task.sleep(for: .milliseconds(20))
        network.simulatePacketLoss = false
        let resumed = try await waiting.value
        precondition(resumed.0 == Data("fixture".utf8) && NetworkStub.requestCount == 2)

        // Enabling a simulation cancels an existing real request, then applies the new mode.
        NetworkStub.holdRequests(true)
        let inFlight = Task { try await network.data(for: request, session: session) }
        for _ in 0..<100 {
            if NetworkStub.requestCount == 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(NetworkStub.requestCount == 3)
        network.simulatePacketLoss = true
        try await Task.sleep(for: .milliseconds(20))
        precondition(NetworkStub.requestCount == 3)
        network.simulateOffline = true
        await expectError(.notConnectedToInternet) { try await inFlight.value }
        NetworkStub.holdRequests(false)
        network.simulateOffline = false
        let cancelled = Task { try await network.data(for: request, session: session) }
        try await Task.sleep(for: .milliseconds(20))
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancellation ignored") }
        catch is CancellationError {} catch { preconditionFailure("Unexpected cancellation: \(error)") }
        precondition(NetworkStub.requestCount == 3)
        network.simulatePacketLoss = false
        _ = try await network.data(for: request, session: session)
        precondition(NetworkStub.requestCount == 4)
        print("Network checks passed: startup flags, real-path restoration, offline precedence, delayed timeout, live toggles and cancellation.")
    }
}
