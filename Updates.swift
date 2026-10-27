import SwiftUI
import AppKit
import Observation

// Only stable MAJOR.MINOR.PATCH versions are eligible for update suggestions.
struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]
    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let components = text.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }
        var numbers: [Int] = []
        for component in components {
            guard !component.isEmpty, component.allSatisfy({ $0.isASCII && $0.isNumber }),
                  component.count == 1 || component.first != "0", let number = Int(component) else { return nil }
            numbers.append(number)
        }
        parts = numbers
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct GitHubRelease: Codable {
    let tag_name: String
    let html_url: URL
    let published_at: Date?
    let draft: Bool
    let prerelease: Bool

    var version: ReleaseVersion? { ReleaseVersion(tag_name) }
    var isValid: Bool {
        !draft && !prerelease && version != nil && published_at != nil &&
        html_url.scheme == "https" && html_url.host == "github.com" &&
        html_url.path.hasPrefix("/GabrielDelepine/codex-costs/releases/tag/") &&
        html_url.user == nil && html_url.password == nil && html_url.port == nil
    }
    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(Self.self, from: data)
        guard release.isValid else { throw URLError(.cannotParseResponse) }
        return release
    }
}

@MainActor @Observable final class ReleaseUpdates {
    enum Phase { case checking, available, current, ahead, failed, noRelease, unsupported }
    var phase: Phase = .checking
    private(set) var checking = false
    private(set) var latest: GitHubRelease?
    private(set) var currentRelease: GitHubRelease?
    var automaticallyChecks: Bool {
        didSet { defaults.set(automaticallyChecks, forKey: "automaticallyCheckForReleases") }
    }
    let currentVersion: String
    private let defaults: UserDefaults
    private let session: URLSession
    private var lastAttempt: Date?
    private let api = "https://api.github.com/repos/GabrielDelepine/codex-costs/releases"
    private let latestKey = "latestAppRelease"
    private var currentKey: String { "appRelease-" + currentVersion }

    init(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
         defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.session = session
        automaticallyChecks = defaults.object(forKey: "automaticallyCheckForReleases") as? Bool ?? true
        if let data = defaults.data(forKey: latestKey) { latest = try? GitHubRelease.decode(data) }
        if let data = defaults.data(forKey: currentKey), let release = try? GitHubRelease.decode(data),
           release.version == ReleaseVersion(currentVersion) { currentRelease = release }
    }
    var updateAvailable: Bool {
        guard let current = ReleaseVersion(currentVersion), let remote = latest?.version else { return false }
        return remote > current
    }
    func showAvailableRelease() {
        if updateAvailable { phase = .available }
    }
    func isDue(at now: Date) -> Bool {
        guard automaticallyChecks else { return false }
        if let attempt = lastAttempt, now >= attempt, now.timeIntervalSince(attempt) < 3600 { return false }
        guard let success = defaults.object(forKey: "lastAppReleaseCheck") as? Date, now >= success else { return true }
        return now.timeIntervalSince(success) >= 72 * 3600
    }
    private func fetch(_ suffix: String) async throws -> Data? {
        var request = URLRequest(url: URL(string: api + suffix)!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Codex-Costs", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
    func check(manual: Bool = false, now: Date = Date()) async {
        guard !checking, manual || isDue(at: now) else { return }
        guard let installed = ReleaseVersion(currentVersion) else { phase = .unsupported; return }
        checking = true; phase = .checking; lastAttempt = now
        defer { checking = false }
        do {
            guard let data = try await fetch("/latest") else {
                latest = nil; defaults.removeObject(forKey: latestKey)
                defaults.set(now, forKey: "lastAppReleaseCheck")
                phase = .noRelease
                return
            }
            let release = try GitHubRelease.decode(data)
            guard let remote = release.version else { throw URLError(.cannotParseResponse) }
            latest = release
            defaults.set(data, forKey: latestKey)
            defaults.set(now, forKey: "lastAppReleaseCheck")
            if release.version == installed {
                currentRelease = release
                defaults.set(data, forKey: currentKey)
            } else if currentRelease == nil {
                // Publication dates are optional details: failure must not hide an available update.
                for tag in ["v" + currentVersion, currentVersion] {
                    do {
                        if let currentData = try await fetch("/tags/" + tag),
                           let current = try? GitHubRelease.decode(currentData), current.version == installed {
                            currentRelease = current
                            defaults.set(currentData, forKey: currentKey)
                            break
                        }
                    } catch { break }
                }
            }
            if remote > installed { phase = .available }
            else if remote == installed { phase = .current }
            else { phase = .ahead }
        } catch {
            // Preserve the last known update indicator, but never report a failed check as current.
            phase = .failed
        }
    }
    func versionLabel(_ version: String, date: Date?) -> String {
        let text: String
        if let date {
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            text = formatter.string(from: date)
        } else { text = "Release date unavailable" }
        let label = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return "\(label) (\(text))"
    }
}

struct UpdatesView: View {
    @Bindable var updates: ReleaseUpdates
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch updates.phase {
        case .checking: return "Checking for updates…"
        case .available: return "A new version of Codex Costs is available"
        case .current: return "You’re up to date"
        case .ahead: return "You’re running a development version"
        case .failed: return "Unable to check for updates"
        case .noRelease: return "No public release available"
        case .unsupported: return "Unable to compare versions"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            if updates.phase == .checking {
                HStack { ProgressView().controlSize(.small); Text("Retrieving release information from GitHub.") }
            } else if updates.phase == .failed {
                Text("Couldn’t retrieve release information from GitHub. Please try again later.")
            } else if updates.phase == .noRelease {
                Text("No stable release has been published on GitHub yet.")
            } else if updates.phase == .unsupported {
                Text("This build does not have a supported release version.")
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        Text("Your version").foregroundStyle(.secondary)
                        Text(updates.versionLabel(updates.currentVersion, date: updates.currentRelease?.published_at))
                    }
                    if let latest = updates.latest {
                        GridRow {
                            Text("Latest version").foregroundStyle(.secondary)
                            Text(updates.versionLabel(latest.tag_name, date: latest.published_at))
                        }
                    }
                }.textSelection(.enabled)
                if updates.phase == .available {
                    Text("Open the GitHub release page to download and install the update.")
                } else if updates.phase == .current {
                    Text("You have the latest stable release of Codex Costs.")
                } else {
                    Text("This version has not been released yet.")
                }
            }
            Toggle("Automatically check for updates", isOn: $updates.automaticallyChecks)
                .toggleStyle(.checkbox)
                .help("Checks GitHub every three days while the app is running, including after reopening or waking. Does not download or install updates.")
                .onChange(of: updates.automaticallyChecks) { _, enabled in
                    if enabled { Task { await updates.check() } }
                }
            HStack {
                Spacer()
                Button(updates.phase == .available ? "Later" : updates.phase == .failed || updates.phase == .checking ? "Cancel" : "OK") { dismiss() }
                    .keyboardShortcut(updates.phase == .available || updates.phase == .failed || updates.phase == .checking ? .cancelAction : .defaultAction)
                if updates.phase == .available, let latest = updates.latest {
                    Button("View Release on GitHub") {
                        NSWorkspace.shared.open(latest.html_url)
                        dismiss()
                    }.keyboardShortcut(.defaultAction)
                } else if updates.phase == .failed {
                    Button("Try Again") { Task { await updates.check(manual: true) } }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24).frame(width: 460).fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, Locale.autoupdatingCurrent)
        .onExitCommand { dismiss() }
    }
}
