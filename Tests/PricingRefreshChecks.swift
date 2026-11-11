import Foundation

@main struct PricingRefreshChecks {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var schedule = PricingRefreshSchedule()
        precondition(schedule.isDue(at: now, lastSuccess: nil, hasCatalog: false))
        // A missing/corrupt cache must not be hidden by a recent download preference.
        precondition(schedule.isDue(at: now, lastSuccess: now, hasCatalog: false))
        precondition(!schedule.isDue(at: now.addingTimeInterval(21599), lastSuccess: now, hasCatalog: true))
        precondition(schedule.isDue(at: now.addingTimeInterval(21600), lastSuccess: now, hasCatalog: true))
        var attempt = now
        for delay: TimeInterval in [60, 300, 900, 3600, 3600] {
            schedule.started(at: attempt)
            let finished = attempt.addingTimeInterval(20)
            schedule.failed(at: finished)
            precondition(!schedule.isDue(at: finished.addingTimeInterval(delay - 1), lastSuccess: nil, hasCatalog: true))
            precondition(schedule.isDue(at: finished.addingTimeInterval(delay), lastSuccess: nil, hasCatalog: true))
            attempt = finished.addingTimeInterval(delay)
        }
        // Network flapping cannot bypass the one-minute cooldown, or lose an early reconnect.
        let lastAttempt = schedule.lastAttempt!
        schedule.networkRestored(at: lastAttempt.addingTimeInterval(30))
        schedule.networkRestored(at: lastAttempt.addingTimeInterval(40))
        precondition(!schedule.isDue(at: lastAttempt.addingTimeInterval(59), lastSuccess: nil, hasCatalog: true))
        precondition(schedule.isDue(at: lastAttempt.addingTimeInterval(60), lastSuccess: nil, hasCatalog: true))
        schedule.succeeded()
        schedule.networkRestored(at: attempt)
        precondition(!schedule.isDue(at: attempt, lastSuccess: attempt, hasCatalog: true))
        schedule.started(at: attempt)
        schedule.failed(at: attempt)
        precondition(schedule.retryAt == attempt.addingTimeInterval(60))
        // A later reconnect can retry immediately instead of waiting out a long backoff.
        schedule.failed(at: attempt)
        schedule.networkRestored(at: attempt.addingTimeInterval(120))
        precondition(schedule.isDue(at: attempt.addingTimeInterval(120), lastSuccess: nil, hasCatalog: true))
        print("Pricing refresh checks passed: cadence, missing cache, backoff, reconnect cooldown and reset.")
    }
}
