import Foundation

// A local archive of parsed metadata/counters only. The log cache remains the sole
// parser, and this actor serializes observation, retention and atomic persistence.
actor ObservedHistory {
    struct Period: Codable { var start: Date; var lastCheck: Date }
    struct Archive: Codable {
        let version: Int
        var sessions: [Session]
        var periods: [Period]
    }
    struct Snapshot {
        let sessions: [Session]
        let days: Set<Date>
        let errors: [String]
        let summary: String
        let periods: [Period]
    }
    static let location = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CodexCosts/history.json")
    private let logs: SessionCache
    private let root: URL
    private let location: URL
    private var records: [String: Session] = [:]
    private var current: [Session] = []
    private var periods: [Period] = []
    private var loaded = false
    private var persistenceBlocked = false
    private var newPeriod = true
    private var storageError: String?
    init(root: URL = Logs.root, location: URL = ObservedHistory.location) {
        self.root = root; self.location = location; self.logs = SessionCache(root: root)
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        guard FileManager.default.fileExists(atPath: location.path) else { return }
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: location))
            guard archive.version == 1 else { throw Failure.message("Unsupported history version") }
            records = Dictionary(archive.sessions.filter { !$0.isGuardianReview }.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            periods = archive.periods
        } catch {
            persistenceBlocked = true
            storageError = "Saved history cannot be read. It has not been overwritten. Clear retained history to start a new archive."
        }
    }
    private func save() {
        guard !persistenceBlocked else { return }
        do {
            let data = try JSONEncoder().encode(Archive(version: 1, sessions: records.values.sorted { $0.id < $1.id }, periods: periods))
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: location, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
            storageError = nil
        } catch { storageError = "History could not be saved. Observed usage is retained in memory only until a save succeeds." }
    }
    func refresh(range: DayRange, now: Date = Date()) async -> Snapshot {
        load()
        let days = await logs.conversationDays()
        let observedDays = Set(records.values.map { Calendar.current.startOfDay(for: $0.date) })
        let folders = days.union(observedDays).sorted().flatMap { DayRange($0, $0).folders(root: root) }
        let result = await logs.scan(folders: folders)
        current = result.sessions
        // Replace snapshots by ID; never add cumulative counters from separate scans.
        for id in Array(records.keys) { records[id]?.sourceAvailable = false }
        for id in result.excludedIDs { records.removeValue(forKey: id) }
        for session in current { records[session.id] = session }
        // Only scans without reported read errors contribute an observation interval.
        // A restart, sleep or long gap starts a new interval rather than claiming coverage.
        if result.errors.isEmpty {
            if !newPeriod, let last = periods.last, now >= last.lastCheck,
               now.timeIntervalSince(last.lastCheck) <= 120 {
                periods[periods.count - 1].lastCheck = now
            } else { periods.append(Period(start: now, lastCheck: now)) }
            newPeriod = false
        } else { newPeriod = true }
        save()
        return snapshot(range: range, errors: result.errors)
    }
    func clear(range: DayRange) async -> Snapshot {
        _ = await refresh(range: range)
        // Forget retained snapshots and coverage, then keep only currently readable sources.
        records = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        periods = []; newPeriod = true; persistenceBlocked = false
        save()
        return snapshot(range: range, errors: [])
    }
    private func snapshot(range: DayRange, errors: [String]) -> Snapshot {
        let calendar = Calendar.current
        let sessions = records.values.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= range.start && day <= range.end
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        let days = Set(records.values.map { calendar.startOfDay(for: $0.date) })
        let summary: String
        if let first = periods.first, let last = periods.last {
            summary = "Observed \(first.start.formatted(date: .abbreviated, time: .shortened)) – \(last.lastCheck.formatted(date: .abbreviated, time: .shortened)) across \(periods.count) observation period(s). Gaps and sessions removed between checks may be missing."
        } else { summary = "No successful observation periods recorded. History may be incomplete." }
        return Snapshot(sessions: sessions, days: days, errors: errors + [storageError].compactMap { $0 }, summary: summary, periods: periods)
    }
}
