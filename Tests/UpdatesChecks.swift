import Foundation

final class ReleaseStub: URLProtocol {
    static var responses: [String: (Int, Data)] = [:]
    static var paths: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.paths.append(path)
        let (status, data) = Self.responses[path] ?? (404, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct UpdatesChecks {
    static func release(_ tag: String, prerelease: Bool = false, draft: Bool = false,
                        url: String? = nil, date: String? = "2026-10-27T10:00:00Z") -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "prerelease": prerelease, "draft": draft,
            "html_url": url ?? "https://github.com/GabrielDelepine/codex-costs/releases/tag/\(tag)",
            "published_at": date as Any? ?? NSNull()
        ])
    }
    @MainActor static func main() async {
        precondition(ReleaseVersion("v1.10.0")! > ReleaseVersion("1.9.0")!)
        precondition(ReleaseVersion("2.0.0")! > ReleaseVersion("1.99.99")!)
        for tag in ["1.2", "01.2.3", "1.2.3-beta.1", "1.2.3.4", "-1.2.3", "1.2.3junk"] {
            precondition(ReleaseVersion(tag) == nil)
        }
        for invalid in [release("1.2.0", prerelease: true), release("1.2.0", draft: true),
                        release("1.2.0", url: "https://example.com/update"), release("1.2.0", date: nil),
                        release("1.2.0-beta.1")] {
            precondition((try? GitHubRelease.decode(invalid)) == nil)
        }
        let suite = "CodexCosts-UpdatesChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let prefix = "/repos/GabrielDelepine/codex-costs/releases"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let updates = ReleaseUpdates(currentVersion: "1.1.0", defaults: defaults, session: session)
        precondition(updates.automaticallyChecks && updates.isDue(at: now))
        ReleaseStub.responses = [prefix + "/latest": (200, release("v1.10.0")),
                                 prefix + "/tags/1.1.0": (200, release("1.1.0"))]
        await updates.check(now: now)
        precondition(updates.phase == .available && updates.updateAvailable && !updates.checking)
        precondition(updates.currentRelease?.tag_name == "1.1.0")
        precondition(!updates.isDue(at: now.addingTimeInterval(72 * 3600 - 1)))
        precondition(updates.isDue(at: now.addingTimeInterval(72 * 3600)))
        let count = ReleaseStub.paths.count
        await updates.check(now: now.addingTimeInterval(1))
        precondition(ReleaseStub.paths.count == count)
        let restored = ReleaseUpdates(currentVersion: "1.1.0", defaults: defaults, session: session)
        precondition(restored.updateAvailable && restored.currentRelease != nil && !restored.isDue(at: now))
        updates.automaticallyChecks = false
        precondition(!updates.isDue(at: now.addingTimeInterval(100 * 3600)))
        precondition(!ReleaseUpdates(currentVersion: "1.1.0", defaults: defaults, session: session).automaticallyChecks)
        ReleaseStub.responses[prefix + "/latest"] = (503, Data())
        await updates.check(manual: true, now: now.addingTimeInterval(1))
        precondition(updates.phase == .failed && updates.updateAvailable)
        updates.showAvailableRelease()
        precondition(updates.phase == .available)
        updates.automaticallyChecks = true
        precondition(!updates.isDue(at: now.addingTimeInterval(3600)))
        precondition(updates.isDue(at: now.addingTimeInterval(72 * 3600)))
        ReleaseStub.responses[prefix + "/latest"] = (200, release("1.1.0"))
        await updates.check(manual: true, now: now.addingTimeInterval(2))
        precondition(updates.phase == .current && !updates.updateAvailable)
        ReleaseStub.responses[prefix + "/latest"] = (200, release("1.0.0"))
        await updates.check(manual: true, now: now.addingTimeInterval(3))
        precondition(updates.phase == .ahead && !updates.updateAvailable)
        ReleaseStub.responses[prefix + "/latest"] = (404, Data())
        await updates.check(manual: true, now: now.addingTimeInterval(4))
        precondition(updates.phase == .noRelease && !updates.updateAvailable)
        ReleaseStub.responses[prefix + "/latest"] = (200, Data("invalid JSON".utf8))
        await updates.check(manual: true, now: now.addingTimeInterval(5))
        precondition(updates.phase == .failed)
        // Missing publication metadata for an older/local build must not hide a valid update.
        let unknown = ReleaseUpdates(currentVersion: "0.9.0", defaults: defaults, session: session)
        ReleaseStub.responses[prefix + "/latest"] = (200, release("1.2.0"))
        await unknown.check(manual: true, now: now)
        precondition(unknown.phase == .available && unknown.currentRelease == nil)
        precondition(unknown.versionLabel("0.9.0", date: nil) == "0.9.0 (Release date unavailable)")
        // A failed automatic attempt retries in one hour, including after clock rollback.
        defaults.removeObject(forKey: "lastAppReleaseCheck")
        let failing = ReleaseUpdates(currentVersion: "1.1.0", defaults: defaults, session: session)
        ReleaseStub.responses[prefix + "/latest"] = (403, Data())
        await failing.check(now: now)
        precondition(!failing.isDue(at: now.addingTimeInterval(3599)))
        precondition(failing.isDue(at: now.addingTimeInterval(3600)))
        precondition(failing.isDue(at: now.addingTimeInterval(-1)))
        let unsupported = ReleaseUpdates(currentVersion: "", defaults: defaults, session: session)
        await unsupported.check(manual: true)
        precondition(unsupported.phase == .unsupported)
        print("Release update checks passed (synthetic HTTP responses and isolated preferences).")
    }
}
