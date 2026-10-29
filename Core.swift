import Foundation

struct Price: Decodable {
    let priceInMicrodollars: Decimal
    let currency: String
    let microdollarsPerDollar: Decimal
    let priceAppliesToTokenCount: Decimal
    func cost(_ tokens: Int64) throws -> Decimal {
        guard currency == "USD", priceInMicrodollars >= 0, microdollarsPerDollar > 0, priceAppliesToTokenCount > 0 else { throw Failure.message("Invalid price") }
        return Decimal(tokens) * priceInMicrodollars / microdollarsPerDollar / priceAppliesToTokenCount
    }
}
struct Rates: Decodable {
    let input: Price?, output: Price?, cachedInput: Price?
    let cacheWriteWith30MinuteRetention: Price?, cacheWriteWith12HourRetention: Price?
}
struct ContextRule: Decodable { let status: String; let inputTokenThreshold: Int64? }
struct ModelRate: Decodable {
    let label: String
    let contextSelection: ContextRule
    let shortContext: Rates?, longContext: Rates?, unspecifiedContext: Rates?
}
struct Catalog: Decodable {
    let schemaVersion: Int
    let fetchedAt: String
    let expiresAt: String
    let pricing: [String: [String: ModelRate]]
    static func decode(_ data: Data) throws -> Catalog {
        let result = try JSONDecoder().decode(Catalog.self, from: data)
        guard result.schemaVersion == 5, result.pricing["standard"]?.isEmpty == false,
              parseDate(result.fetchedAt) != nil else { throw Failure.message("Unsupported pricing format or version") }
        return result
    }
}
enum Failure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
func parseDate(_ value: String) -> Date? {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
let tokenKeys = ["input_tokens", "cached_input_tokens", "cache_write_input_tokens", "output_tokens", "reasoning_output_tokens"]
struct Usage: Equatable {
    var input: Int64 = 0, cache: Int64 = 0, write: Int64 = 0, output: Int64 = 0, reasoning: Int64 = 0
    init() {}
    init(_ object: [String: Any]) {
        input = (object["input_tokens"] as? NSNumber)?.int64Value ?? 0
        cache = (object["cached_input_tokens"] as? NSNumber)?.int64Value ?? 0
        write = (object["cache_write_input_tokens"] as? NSNumber)?.int64Value ?? 0
        output = (object["output_tokens"] as? NSNumber)?.int64Value ?? 0
        reasoning = (object["reasoning_output_tokens"] as? NSNumber)?.int64Value ?? 0
    }
    var isConsistent: Bool { numbers.allSatisfy { $0 >= 0 } && input >= cache + write && reasoning <= output }
    static func + (a: Usage, b: Usage) -> Usage {
        var u = Usage(); u.input = a.input+b.input; u.cache = a.cache+b.cache; u.write = a.write+b.write; u.output = a.output+b.output; u.reasoning = a.reasoning+b.reasoning; return u
    }
    var numbers: [Int64] { [input, cache, write, output, reasoning] }
    static func - (a: Usage, b: Usage) -> Usage {
        var u = Usage(); u.input = a.input-b.input; u.cache = a.cache-b.cache; u.write = a.write-b.write; u.output = a.output-b.output; u.reasoning = a.reasoning-b.reasoning; return u
    }
}
struct AppliedPricing { let context: String; let rates: Rates }
struct PricingBreakdown {
    let model: String
    let context: String
    let rates: Rates
    var used: [Bool]
    var id: String { model + "\n" + context }
}
struct RequestCostBreakdown {
    let context: String
    let ordinaryInput: Decimal, cachedInput: Decimal, output: Decimal
    var total: Decimal { ordinaryInput + cachedInput + output }
}
struct Call {
    let model: String?
    let usage: Usage
    var timestamp: Date? = nil
    func pricingBreakdown(_ catalog: Catalog?) -> PricingBreakdown? {
        guard estimate(catalog).cost != nil, let model, let applied = try? appliedPricing(catalog) else { return nil }
        return PricingBreakdown(model: model, context: applied.context, rates: applied.rates,
                                used: [usage.input - usage.cache - usage.write > 0, usage.cache > 0, usage.output > 0, false, false])
    }
    func appliedPricing(_ catalog: Catalog?) throws -> AppliedPricing {
        guard let model else { throw Failure.message("Model not recorded for request") }
        guard let published = catalog?.pricing["standard"]?[model] else { throw Failure.message("Standard price unavailable") }
        if let flat = published.unspecifiedContext {
            return AppliedPricing(context: "Published rates without a context threshold", rates: flat)
        }
        guard published.contextSelection.status == "known", let threshold = published.contextSelection.inputTokenThreshold else {
            throw Failure.message("Unknown context threshold")
        }
        let long = usage.input > threshold
        guard let rates = long ? published.longContext : published.shortContext else { throw Failure.message("Context prices unavailable") }
        return AppliedPricing(context: long ? "Long context" : "Short context", rates: rates)
    }
    func costBreakdown(_ catalog: Catalog?) throws -> RequestCostBreakdown {
        let u = usage
        guard u.isConsistent else { throw Failure.message("Inconsistent token counters") }
        let applied = try appliedPricing(catalog)
        // Retention is not present in Codex token counters: never guess it.
        guard u.write == 0 else { throw Failure.message("Cache-write retention unknown") }
        func component(_ tokens: Int64, _ price: Price?) throws -> Decimal {
            if tokens == 0 { return 0 }
            guard let price else { throw Failure.message("Required price unknown (null)") }
            return try price.cost(tokens)
        }
        return try RequestCostBreakdown(context: applied.context,
                                        ordinaryInput: component(u.input-u.cache-u.write, applied.rates.input),
                                        cachedInput: component(u.cache, applied.rates.cachedInput),
                                        output: component(u.output, applied.rates.output))
    }
    func estimate(_ catalog: Catalog?) -> Estimate {
        do {
            let breakdown = try costBreakdown(catalog)
            return Estimate(cost: breakdown.total, reason: nil, context: breakdown.context)
        } catch { return .unavailable(error.localizedDescription) }
    }
}
struct Session: Identifiable {
    let id: String, file: URL, date: Date, title: String, models: [String], calls: [Call], usage: Usage, issues: [String]
    var guardianSource = false
    var isGuardianReview: Bool {
        guardianSource || models.contains("codex-auto-review") || title.caseInsensitiveCompare("Guardian review") == .orderedSame
    }
    func titled(_ newTitle: String) -> Session {
        Session(id: id, file: file, date: date, title: newTitle, models: models, calls: calls, usage: usage, issues: issues, guardianSource: guardianSource)
    }
    func scoped(to range: DayRange) -> Session {
        let selected = calls.filter { call in
            return call.timestamp.map { range.contains($0) } ?? false
        }
        return Session(id: id, file: file, date: date, title: title, models: models,
                       calls: selected, usage: selected.reduce(Usage()) { $0 + $1.usage },
                       issues: issues, guardianSource: guardianSource)
    }
    var firstActivity: Date? { calls.compactMap(\.timestamp).min() }
    var activityRange: DayRange? {
        let dates = calls.compactMap(\.timestamp)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return DayRange(first, last)
    }
    var codexURL: URL? {
        guard !isGuardianReview else { return nil }
        return URL(string: "codex://threads/" + id)
    }
    func estimate(_ catalog: Catalog?) -> Estimate {
        guard models.count == 1 else { return .unavailable(models.isEmpty ? "Model not recorded" : "Multiple models used") }
        guard issues.isEmpty else { return .unavailable(issues.joined(separator: " · ")) }
        guard !calls.isEmpty else { return .unavailable("No usage recorded") }
        var sum: Decimal = 0
        var contexts = Set<String>()
        for call in calls {
            guard call.model == models[0] else { return .unavailable("Unknown model for a request") }
            let estimate = call.estimate(catalog)
            guard let cost = estimate.cost else { return estimate }
            sum += cost; contexts.insert(estimate.context)
        }
        return Estimate(cost: sum, reason: nil, context: contexts.sorted().joined(separator: " + "))
    }
    func pricingBreakdowns(_ catalog: Catalog?) -> [PricingBreakdown] {
        var groups: [String: PricingBreakdown] = [:]
        for call in calls {
            guard let applied = call.pricingBreakdown(catalog) else { continue }
            if var previous = groups[applied.id] {
                previous.used = zip(previous.used, applied.used).map { $0 || $1 }
                groups[applied.id] = previous
            } else { groups[applied.id] = applied }
        }
        return groups.values.sorted { $0.id < $1.id }
    }
}
struct Estimate {
    let cost: Decimal?, reason: String?, context: String
    static func unavailable(_ reason: String) -> Estimate { Estimate(cost: nil, reason: reason, context: "") }
}
func dollars(_ value: Decimal?) -> String {
    guard let value else { return "—" }
    let f = NumberFormatter(); f.locale = .autoupdatingCurrent; f.numberStyle = .decimal; f.minimumFractionDigits = 4; f.maximumFractionDigits = 4
    return f.string(from: value as NSDecimalNumber).map { "$" + $0 } ?? "—"
}
struct ScanResult {
    let sessions: [Session]
    let errors: [String]
    let changed: Bool
    let filesRead: Int
    let updatedSessionIDs: Set<String>
}
enum Logs {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    static func guardianSource(_ payload: [String: Any]) -> Bool {
        let source = payload["source"] as? [String: Any]
        let subagent = source?["subagent"] as? [String: Any]
        return subagent?["other"] as? String == "guardian"
    }
    static func creationDay(_ file: URL) -> Date? {
        let name = file.lastPathComponent
        guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return f.date(from: String(name.dropFirst(8).prefix(10)))
    }
    static func read(_ url: URL, titles: [String: String]) throws -> Session {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.message("Unreadable log") }
        let lines = text.components(separatedBy: "\n")
        var id = "", model: String?, models: [String] = [], calls: [Call] = [], previous = Usage(), issues = Set<String>()
        var date = Date.distantPast, guardian = false, hasSessionMeta = false
        // Rollout filenames encode the local creation time, not UTC.
        let name = url.deletingPathExtension().lastPathComponent
        if name.hasPrefix("rollout-"), name.count >= 64 {
            let suffix = String(name.dropFirst(8)); let stamp = String(suffix.prefix(19)); id = String(suffix.dropFirst(20))
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"; date = f.date(from: stamp) ?? date
        }
        for (index, line) in lines.enumerated() where !line.isEmpty {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                if index == lines.count-1 && !text.hasSuffix("\n") { break }
                issues.insert("Invalid JSON line"); continue
            }
            let p = event["payload"] as? [String: Any] ?? [:]
            if event["type"] as? String == "session_meta", !hasSessionMeta {
                // Fork history may contain parent metadata; the first entry owns this rollout.
                hasSessionMeta = true
                guardian = guardian || guardianSource(p)
                id = p["id"] as? String ?? id
                if date == .distantPast, let stamp = p["timestamp"] as? String { date = parseDate(stamp) ?? date }
            }
            if event["type"] as? String == "turn_context" {
                model = p["model"] as? String
                if let model, !models.contains(model) { models.append(model) }
            }
            guard event["type"] as? String == "event_msg", p["type"] as? String == "token_count", let info = p["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any] else { continue }
            let current = Usage(total), delta = current - previous
            previous = current
            if delta.numbers.allSatisfy({ $0 == 0 }) { continue }
            guard delta.numbers.allSatisfy({ $0 >= 0 }) else { issues.insert("Token counters reset"); continue }
            guard tokenKeys.allSatisfy({ total[$0] is NSNumber }), let last = info["last_token_usage"] as? [String: Any], tokenKeys.allSatisfy({ last[$0] is NSNumber }) else { issues.insert("Incomplete token counters"); continue }
            guard Usage(last) == delta else { issues.insert("Usage delta does not match a request"); continue }
            calls.append(Call(model: model, usage: delta, timestamp: (event["timestamp"] as? String).flatMap(parseDate)))
        }
        guard !id.isEmpty else { throw Failure.message("Missing conversation ID") }
        return Session(id: id, file: url, date: date, title: titles[id] ?? "Untitled", models: models, calls: calls, usage: previous, issues: issues.sorted(), guardianSource: guardian)
    }
}

// Local calendar days keep date ranges correct across daylight-saving changes.
struct DayRange: Equatable {
    let start: Date
    let end: Date
    init(_ start: Date, _ end: Date, calendar: Calendar = .current) {
        self.start = calendar.startOfDay(for: min(start, end))
        self.end = calendar.startOfDay(for: max(start, end))
    }
    static var today: DayRange { DayRange(Date(), Date()) }
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }
    var label: String {
        let f = DateFormatter(); f.locale = .autoupdatingCurrent; f.dateStyle = .medium; f.timeStyle = .none
        return start == end ? f.string(from: start) : f.string(from: start) + " – " + f.string(from: end)
    }
}

// Only this actor owns parsed logs. Changes trigger full reads of affected files,
// never incremental JSON parsing. Title changes do not reread session contents.
actor SessionCache {
    struct Stamp: Equatable {
        let size: UInt64
        let modified: Date
        let created: Date
        let inode: UInt64
        init(_ url: URL) throws {
            let a = try FileManager.default.attributesOfItem(atPath: url.path)
            size = (a[.size] as? NSNumber)?.uint64Value ?? 0
            modified = a[.modificationDate] as? Date ?? .distantPast
            created = a[.creationDate] as? Date ?? .distantPast
            inode = (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        }
    }
    struct Entry { let stamp: Stamp; let session: Session }
    let root: URL
    private var entries: [URL: Entry] = [:]
    private var titles: [String: String] = [:]
    private var indexStamp: Stamp?
    private var lastErrors: [String] = []
    private var dayDirectories: [URL: (stamp: Stamp, files: [URL])] = [:]
    private var archiveStamp: Stamp?
    private var archiveFiles: [URL] = []
    init(root: URL = Logs.root) { self.root = root.resolvingSymlinksInPath() }
    private func archivedFiles() throws -> [URL] {
        let folder = root.appendingPathComponent("archived_sessions")
        guard FileManager.default.fileExists(atPath: folder.path) else {
            archiveStamp = nil; archiveFiles = []; return []
        }
        let stamp = try Stamp(folder)
        if archiveStamp != stamp {
            archiveFiles = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { Logs.creationDay($0) != nil }
            archiveStamp = stamp
        }
        return archiveFiles
    }
    // Discover all creation folders: an old rollout can contain today's activity.
    // Directory listings and full parsed files are cached independently.
    private func discoveredFiles() throws -> Set<URL> {
        let fm = FileManager.default
        func directories(_ url: URL) throws -> [URL] {
            guard fm.fileExists(atPath: url.path) else { return [] }
            return try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]).filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && Int($0.lastPathComponent) != nil
            }
        }
        var files = Set<URL>(), seen = Set<URL>()
        for year in try directories(root.appendingPathComponent("sessions")) {
            for month in try directories(year) {
                for day in try directories(month) {
                    seen.insert(day)
                    let stamp = try Stamp(day)
                    if dayDirectories[day]?.stamp != stamp {
                        let urls = try fm.contentsOfDirectory(at: day, includingPropertiesForKeys: nil)
                        dayDirectories[day] = (stamp, urls.filter {
                            $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl"
                        })
                    }
                    files.formUnion(dayDirectories[day]?.files ?? [])
                }
            }
        }
        for url in Array(dayDirectories.keys) where !seen.contains(url) { dayDirectories.removeValue(forKey: url) }
        files.formUnion(try archivedFiles())
        return files
    }
    func scan() -> ScanResult {
        let fm = FileManager.default
        var changed = false, reads = 0, errors: [String] = []
        var updatedSessionIDs = Set<String>()
        let index = root.appendingPathComponent("session_index.jsonl")
        if fm.fileExists(atPath: index.path) {
            do {
                let stamp = try Stamp(index)
                if stamp != indexStamp {
                    let text = try String(contentsOf: index, encoding: .utf8)
                    var fresh: [String: String] = [:]
                    let lines = text.components(separatedBy: "\n")
                    for (i, line) in lines.enumerated() where !line.isEmpty {
                        guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                              let id = row["id"] as? String, let title = row["thread_name"] as? String else {
                            if i == lines.count - 1 && !text.hasSuffix("\n") { continue }
                            errors.append("Invalid title-index entry"); continue
                        }
                        fresh[id] = title
                    }
                    changed = changed || fresh != titles
                    titles = fresh; indexStamp = stamp
                }
            } catch { errors.append("Cannot read title index") }
        } else if indexStamp != nil {
            titles = [:]; indexStamp = nil; changed = true
        }
        let files: Set<URL>
        do { files = try discoveredFiles() }
        catch {
            // Do not display stale estimates after an incomplete discovery pass.
            let removed = Set(entries.values.map { $0.session.id })
            entries.removeAll()
            return ScanResult(sessions: [], errors: ["Cannot discover session logs"], changed: true,
                              filesRead: 0, updatedSessionIDs: removed)
        }
        for url in Array(entries.keys) where !files.contains(url) {
            // Removing the preferred copy can expose a cached archive with different usage.
            if let removed = entries.removeValue(forKey: url) { updatedSessionIDs.insert(removed.session.id) }
            changed = true
        }
        for url in files.sorted(by: { $0.path < $1.path }) {
            do {
                let stamp = try Stamp(url)
                if entries[url]?.stamp != stamp {
                    let session = try Logs.read(url, titles: [:])
                    entries[url] = Entry(stamp: stamp, session: session)
                    updatedSessionIDs.insert(session.id)
                    reads += 1; changed = true
                }
            } catch {
                // Keep no stale estimated cost for a file that can no longer be read.
                if let removed = entries.removeValue(forKey: url) {
                    updatedSessionIDs.insert(removed.session.id)
                    changed = true
                }
                errors.append("Cannot read log: " + url.lastPathComponent)
            }
        }
        changed = changed || errors != lastErrors
        lastErrors = errors
        var sessions: [Session] = [], seenIDs = Set<String>()
        let ordered = entries.values.sorted {
            let a = $0.session.file.path, b = $1.session.file.path
            let aArchived = $0.session.file.deletingLastPathComponent().lastPathComponent == "archived_sessions"
            let bArchived = $1.session.file.deletingLastPathComponent().lastPathComponent == "archived_sessions"
            if aArchived != bArchived { return !aArchived }
            return a < b
        }
        for entry in ordered where seenIDs.insert(entry.session.id).inserted {
            let title = titles[entry.session.id] ?? "Untitled"
            let session = entry.session.titled(title)
            if !session.isGuardianReview { sessions.append(session) }
        }
        sessions.sort { a, b in
            if a.date == b.date { return a.id < b.id }
            return a.date < b.date
        }
        return ScanResult(sessions: sessions, errors: errors, changed: changed, filesRead: reads, updatedSessionIDs: updatedSessionIDs)
    }
}
