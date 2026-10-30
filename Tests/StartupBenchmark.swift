import Foundation

// Run with an optimized build of Core.swift. Fixture generation is not timed.
@main struct StartupBenchmark {
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("CodexCosts-Startup-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("sessions/2026/10/27")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let content = String(repeating: "Tool output: café 🦊 e\u{301} and ordinary conversation text.\n", count: 320)
        let response = try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": ["text": content]])
        var bytes = 0
        for file in 1...48 {
            let id = String(format: "00000000-0000-0000-0000-%012d", file)
            var data = Data()
            func append(_ record: [String: Any]) throws {
                data.append(try JSONSerialization.data(withJSONObject: record)); data.append(0x0A)
            }
            try append(["type": "session_meta", "payload": ["id": id]])
            try append(["type": "turn_context", "payload": ["model": "fixture-model"]])
            for request in 1...16 {
                for _ in 0..<8 { data.append(response); data.append(0x0A) }
                func counters(_ n: Int) -> [String: Int] {
                    ["input_tokens": n * 100, "cached_input_tokens": n * 20, "cache_write_input_tokens": 0,
                     "output_tokens": n * 5, "reasoning_output_tokens": n]
                }
                try append(["type": "event_msg", "timestamp": "2026-10-27T10:00:00.123Z",
                            "payload": ["type": "token_count", "info": ["total_token_usage": counters(request), "last_token_usage": counters(1)]]])
            }
            bytes += data.count
            try data.write(to: folder.appendingPathComponent("rollout-2026-10-27T10-00-00-" + id + ".jsonl"))
        }
        print("Synthetic fixture: 48 files, 768 requests, \(bytes) bytes")
        for run in 1...3 {
            let cache = SessionCache(root: root)
            let start = Date()
            let result = await cache.scan()
            let scanned = Date()
            precondition(result.filesRead == 48 && result.sessions.count == 48 && result.errors.isEmpty)
            precondition(result.sessions.allSatisfy { $0.calls.count == 16 && $0.issues.isEmpty && $0.usage.input == 1600 })
            let refresh = await cache.scan()
            let refreshed = Date()
            precondition(refresh.filesRead == 0 && !refresh.changed)
            print("Run \(run): initial scan \(scanned.timeIntervalSince(start)) s; unchanged refresh \(refreshed.timeIntervalSince(scanned)) s")
        }
    }
}
