import Foundation

@main struct DailyUsageChecks {
    static func counters(_ input: Int64, cache: Int64 = 0, output: Int64 = 5) -> [String: Int64] {
        ["input_tokens": input, "cached_input_tokens": cache, "cache_write_input_tokens": 0,
         "output_tokens": output, "reasoning_output_tokens": 0]
    }
    static func event(_ timestamp: String?, total: [String: Int64], last: [String: Int64]) -> [String: Any] {
        var result: [String: Any] = ["type": "event_msg", "payload": ["type": "token_count",
            "info": ["total_token_usage": total, "last_token_usage": last]]]
        if let timestamp { result["timestamp"] = timestamp }
        return result
    }
    static func write(_ events: [[String: Any]], to url: URL, partial: String = "") throws {
        let text = try events.map { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys), as: UTF8.self) }.joined(separator: "\n") + "\n" + partial
        try Data(text.utf8).write(to: url, options: .atomic)
    }
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("CodexCosts-DailyChecks-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("sessions/2026/10/27")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = "00000000-0000-0000-0000-000000000001"
        let file = folder.appendingPathComponent("rollout-2026-10-27T07-44-47-" + id + ".jsonl")
        let header: [[String: Any]] = [["type": "session_meta", "payload": ["id": id]],
                                      ["type": "turn_context", "payload": ["model": "fixture-model"]]]
        let first = event("2026-10-27T10:00:00Z", total: counters(100, cache: 20), last: counters(100, cache: 20))
        let second = event("2026-10-28T10:00:00Z", total: counters(300, cache: 60, output: 10), last: counters(200, cache: 40))
        let unknown = event(nil, total: counters(350, cache: 60, output: 15), last: counters(50))
        try write(header + [first, second, second, unknown], to: file, partial: "{\"type\":")
        let cache = SessionCache(root: root)
        let initial = await cache.scan()
        precondition(initial.filesRead == 1 && initial.sessions.count == 1)
        let session = initial.sessions[0]
        precondition(session.calls.count == 3 && session.issues.isEmpty)
        let day1 = DayRange(parseDate("2026-10-27T10:00:00Z")!, parseDate("2026-10-27T10:00:00Z")!)
        let day2 = DayRange(parseDate("2026-10-28T10:00:00Z")!, parseDate("2026-10-28T10:00:00Z")!)
        precondition(session.activityRange == DayRange(day1.start, day2.end))
        let one = session.scoped(to: day1), two = session.scoped(to: day2)
        precondition(two.activityRange == day2)
        let reordered = Session(id: session.id, file: file, date: .distantPast, title: session.title, models: session.models,
                                calls: [session.calls[1], session.calls[2], session.calls[0]], usage: session.usage, issues: [])
        precondition(reordered.activityRange == session.activityRange)
        precondition(session.scoped(to: session.activityRange!).usage.input == 300)
        precondition(one.calls.count == 1 && one.usage.input == 100)
        precondition(two.calls.count == 1 && two.usage.input == 200)
        let undatedCalls = session.calls.filter { $0.timestamp == nil }
        precondition(undatedCalls.count == 1 && undatedCalls[0].usage.input == 50)
        precondition(session.scoped(to: DayRange(day1.start, day2.end)).usage.input == 300)
        let undatedOnly = Session(id: "undated", file: file, date: session.date, title: "Fixture",
                                  models: session.models, calls: undatedCalls, usage: undatedCalls[0].usage, issues: [])
        precondition(undatedOnly.scoped(to: day1).calls.isEmpty && undatedOnly.scoped(to: day2).calls.isEmpty)
        precondition(undatedOnly.calls.count == 1)
        precondition(undatedOnly.activityRange == nil)
        precondition(session.calls.enumerated().filter { $0.element.timestamp == nil }.first!.offset == 2)
        precondition(session.calls.enumerated().filter { $0.element.timestamp.map { day2.contains($0) } ?? false }.first!.offset == 1)
        let price = Price(priceInMicrodollars: 1, currency: "USD", microdollarsPerDollar: 1_000_000, priceAppliesToTokenCount: 1)
        let rates = Rates(input: price, output: price, cachedInput: price, cacheWriteWith30MinuteRetention: nil, cacheWriteWith12HourRetention: nil)
        let model = ModelRate(label: "Fixture", contextSelection: ContextRule(status: "known", inputTokenThreshold: 150), shortContext: rates, longContext: rates, unspecifiedContext: nil)
        let catalog = Catalog(schemaVersion: 5, fetchedAt: "2026-10-28T10:00:00Z", expiresAt: "2026-10-29T10:00:00Z", pricing: ["standard": ["fixture-model": model]])
        precondition(one.estimate(catalog).cost == Decimal(105) / 1_000_000)
        precondition(two.estimate(catalog).cost == Decimal(205) / 1_000_000)
        precondition(one.estimate(catalog).context == "Short context" && two.estimate(catalog).context == "Long context")
        precondition(two.estimate(nil).cost == nil)
        precondition(session.estimate(catalog).cost == Decimal(365) / 1_000_000)
        precondition(undatedOnly.estimate(catalog).cost == Decimal(55) / 1_000_000)
        // The selected day's breakdown must reconcile with #21's shared calculation.
        let detailed = try two.calls[0].costBreakdown(catalog)
        precondition(detailed.ordinaryInput == Decimal(160) / 1_000_000)
        precondition(detailed.cachedInput == Decimal(40) / 1_000_000)
        precondition(detailed.output == Decimal(5) / 1_000_000)
        precondition(detailed.total == two.estimate(catalog).cost)
        precondition(one.usage + two.usage == session.scoped(to: DayRange(day1.start, day2.end)).usage)
        var reasoningUsage = Usage(counters(100, cache: 25, output: 20))
        reasoningUsage.reasoning = 10
        let reasoningCall = Call(model: "fixture-model", usage: reasoningUsage)
        let reasoningCost = try reasoningCall.costBreakdown(catalog)
        precondition(reasoningCost.total == Decimal(120) / 1_000_000)
        precondition(reasoningUsage.isConsistent)
        let mixed = Session(id: "mixed", file: file, date: session.date, title: "Fixture", models: ["fixture-model", "other"],
                            calls: session.calls, usage: session.usage, issues: [])
        precondition(mixed.scoped(to: day2).estimate(catalog).cost == nil)
        precondition(Call(model: "fixture-model", usage: Usage(counters(150))).estimate(catalog).context == "Short context")
        precondition(Call(model: "fixture-model", usage: Usage(counters(151))).estimate(catalog).context == "Long context")
        let unchanged = await cache.scan()
        precondition(!unchanged.changed && unchanged.filesRead == 0)
        try write([["id": id, "thread_name": "Renamed fixture"]], to: root.appendingPathComponent("session_index.jsonl"))
        let renamed = await cache.scan()
        precondition(renamed.changed && renamed.filesRead == 0 && renamed.sessions[0].title == "Renamed fixture")
        // A changed old file must reveal new activity without a new creation folder.
        let third = event("2026-10-29T10:00:00Z", total: counters(400, cache: 60, output: 20), last: counters(50))
        try write(header + [first, second, unknown, third], to: file)
        let updated = await cache.scan()
        precondition(updated.filesRead == 1 && updated.sessions[0].calls.count == 4)
        let archive = root.appendingPathComponent("archived_sessions")
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try write(header + [first], to: archive.appendingPathComponent(file.lastPathComponent))
        let duplicate = await cache.scan()
        precondition(duplicate.sessions.count == 1 && duplicate.sessions[0].calls.count == 4)
        try fm.removeItem(at: file)
        let fallback = await cache.scan()
        precondition(fallback.sessions.count == 1 && fallback.sessions[0].calls.count == 1 && fallback.updatedSessionIDs.contains(id))
        // Guardian classification happens after deduplication and reacts to title changes.
        try write([["id": id, "thread_name": "Guardian review"]], to: root.appendingPathComponent("session_index.jsonl"))
        let guardian = await cache.scan()
        precondition(guardian.sessions.isEmpty && guardian.filesRead == 0)
        let invalid = folder.appendingPathComponent("rollout-2026-10-27T08-00-00-00000000-0000-0000-0000-000000000002.jsonl")
        let reset = event("invalid-date", total: counters(10, output: 1), last: counters(10, output: 1))
        try write([["type": "session_meta", "payload": ["id": "other"]]] + [first, reset], to: invalid)
        let resetSession = try Logs.read(invalid, titles: [:])
        precondition(resetSession.issues.contains("Token counters reset") && resetSession.calls.count == 1)
        try write([["type": "session_meta", "payload": ["id": "other"]]] + [reset], to: invalid)
        let invalidDateSession = try Logs.read(invalid, titles: [:])
        precondition(invalidDateSession.calls.count == 1 && invalidDateSession.calls[0].timestamp == nil)
        // Calendar-day inclusion handles both 23-hour and 25-hour DST days.
        var paris = Calendar(identifier: .gregorian); paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        for (stamp, hours) in [("2026-03-29T10:00:00Z", 23), ("2026-10-25T10:00:00Z", 25)] {
            let date = parseDate(stamp)!, range = DayRange(date, date, calendar: paris)
            let next = paris.date(byAdding: .day, value: 1, to: range.end)!
            precondition(next.timeIntervalSince(range.start) == Double(hours * 3600))
            precondition(range.contains(next.addingTimeInterval(-0.001), calendar: paris))
            precondition(!range.contains(next, calendar: paris))
        }
        let midnight = parseDate("2026-10-27T23:30:00Z")!
        let localDay = DayRange(parseDate("2026-10-28T10:00:00Z")!, parseDate("2026-10-28T10:00:00Z")!, calendar: paris)
        precondition(localDay.contains(midnight, calendar: paris))
        try fm.removeItem(at: invalid)
        try fm.removeItem(at: archive)
        let deleted = await cache.scan()
        precondition(deleted.sessions.isEmpty)
        print("Daily usage checks passed")
    }
}
