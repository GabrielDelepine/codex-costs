import SwiftUI
import AppKit
import Observation

@MainActor @Observable final class Store {
    var range = DayRange.today
    var followToday = true
    var availableDays: Set<Date> = []
    var sessions: [Session] = []
    var estimates: [String: Estimate] = [:]
    var catalog: Catalog?
    var networkStatus = ""
    var logStatus = ""
    var historySummary = "History may be incomplete."
    var observationPeriods: [ObservedHistory.Period] = []
    var fetching = false
    var watching = false
    private var watcher: LogWatcher?
    private let history = ObservedHistory()
    private var debounce: Task<Void, Never>?
    private var scanning = false
    private var rescanPending = false
    private var running = false
    private var lastAttempt = Date.distantPast
    private let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodexCosts/pricing.json")
    init() {
        if let data = try? Data(contentsOf: cache) { catalog = try? Catalog.decode(data) }
    }
    func estimate(_ session: Session) -> Estimate {
        estimates[session.id] ?? .unavailable("Usage not processed yet")
    }
    private func updateEstimates() {
        estimates = Dictionary(sessions.map { ($0.id, $0.estimate(catalog)) }, uniquingKeysWith: { _, new in new })
    }
    func select(_ selection: DayRange) {
        followToday = false
        let today = Calendar.current.startOfDay(for: Date())
        range = DayRange(min(selection.start, today), min(selection.end, today))
        Task { await scan() }
    }
    func today() {
        followToday = true; range = .today
        Task { await scan() }
    }
    func refreshPrices(force: Bool = false) async {
        guard !fetching else { return }
        let now = Date()
        let lastSuccess = UserDefaults.standard.object(forKey: "lastDownload") as? Date ?? .distantPast
        guard force || now.timeIntervalSince(max(lastAttempt, lastSuccess)) >= 6*3600 else { return }
        lastAttempt = now; fetching = true
        defer { fetching = false }
        do {
            var request = URLRequest(url: URL(string: "https://tools.pwa.ovh/api/v1/openai-pricing")!)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw Failure.message("Invalid HTTP response") }
            let fresh = try Catalog.decode(data)
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cache, options: .atomic)
            catalog = fresh; updateEstimates()
            UserDefaults.standard.set(now, forKey: "lastDownload")
            networkStatus = ""
        } catch {
            // Avoid leaking localized French OS/network errors into the English UI.
            networkStatus = catalog == nil ? "Pricing update failed. No saved prices available." : "Pricing update failed. Last downloaded prices retained."
        }
    }
    func scan() async {
        if scanning { rescanPending = true; return }
        scanning = true
        repeat {
            rescanPending = false
            if followToday && range != .today { range = .today }
            let selected = range
            let result = await history.refresh(range: selected)
            if result.days != availableDays { availableDays = result.days }
            historySummary = result.summary; observationPeriods = result.periods
            if range == selected {
                if sessions != result.sessions { sessions = result.sessions; updateEstimates() }
                logStatus = result.errors.joined(separator: "\n")
            } else { rescanPending = true }
        } while rescanPending && !Task.isCancelled
        scanning = false
    }
    func clearHistory() async {
        let selected = range
        let result = await history.clear(range: selected)
        historySummary = result.summary; observationPeriods = result.periods
        availableDays = result.days
        if range == selected { if sessions != result.sessions { sessions = result.sessions; updateEstimates() } }
        logStatus = result.errors.joined(separator: "\n")
        await scan()
    }
    func filesChanged() {
        // Cancel only the waiting debounce task, never an in-flight file read.
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.debounce = nil
            await self?.scan()
        }
    }
    func wake() {
        Task { await scan() }
        Task { await refreshPrices() }
    }
    func run() async {
        guard !running else { return }; running = true
        watcher = LogWatcher(root: Logs.root) { [weak self] in
            Task { @MainActor [weak self] in self?.filesChanged() }
        }
        watching = watcher?.isRunning == true
        defer { watcher = nil; watching = false; running = false; debounce?.cancel() }
        await scan()
        Task { await refreshPrices() }
        // Recovery for missed events, sleep, missing folders, midnight and pricing deadlines.
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            await scan()
            Task { await refreshPrices() }
        }
    }
}

@main struct CodexCostsApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup {
            MainView(store: store)
                .environment(\.locale, Locale.autoupdatingCurrent)
                .frame(minWidth: 1080, minHeight: 520)
                .task { await store.run() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.wake() }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in store.wake() }
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 1220, height: 700)
    }
}
struct MainView: View {
    @Bindable var store: Store
    @State private var selection: String?
    @State private var detail: Session?
    @State private var search = ""
    @State private var calendarOpen = false
    @State private var draft = DayRange.today
    @State private var historyOpen = false
    @State private var clearHistory = false
    var filtered: [Session] {
        store.sessions.filter { search.isEmpty || ($0.title + $0.id + $0.models.joined()).localizedCaseInsensitiveContains(search) }
    }
    var total: Decimal { filtered.reduce(0) { $0 + (store.estimate($1).cost ?? 0) } }
    var unavailable: Int { filtered.filter { store.estimate($0).cost == nil }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Codex Costs").font(.title2.bold())
                    Text("Token estimates · Current Standard API rates · USD").foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(dollars(total)).font(.title2.monospacedDigit().bold())
                    Text("\(filtered.count - unavailable) estimated · \(unavailable) unavailable").foregroundStyle(.secondary).font(.caption)
                }
            }.padding(20)
            HStack {
                Button { draft = store.range; calendarOpen = true } label: {
                    Label(store.range.label, systemImage: "calendar")
                }.popover(isPresented: $calendarOpen, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Select a date").font(.headline)
                        RangeCalendar(range: $draft, availableDays: store.availableDays)
                        Text("Shift-click to select a range. Grey days have no conversations.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(draft.label).font(.subheadline.monospacedDigit())
                        HStack {
                            Button("Cancel") { calendarOpen = false }.keyboardShortcut(.cancelAction)
                            Spacer()
                            Button("Apply") { store.select(draft); calendarOpen = false }
                                .disabled(!store.availableDays.contains(draft.start) || !store.availableDays.contains(draft.end))
                                .keyboardShortcut(.defaultAction)
                        }
                    }.padding(14).frame(width: 200)
                }
                Toggle("Auto-select today", isOn: Binding(get: { store.followToday }, set: { value in
                    if value { store.today() } else { store.followToday = false }
                })).toggleStyle(.checkbox)
                    .help("Selects today now and after midnight or wake. Choosing dates turns this off. Enabled on each app launch. Usage updates in either mode.")
                Spacer()
                TextField("Search title, ID or model", text: $search).textFieldStyle(.roundedBorder).frame(width: 240)
                Button {
                    Task { await store.scan() }
                    Task { await store.refreshPrices(force: true) }
                } label: { Image(systemName: "arrow.clockwise") }.help("Check logs and refresh prices")
                    .disabled(store.fetching)
            }.padding(.horizontal, 20).padding(.bottom, 14)
            Text("Usage updates for any selected dates. Auto-select today follows the current day; choosing dates turns it off. Enabled on each launch.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 10)
            Divider()
            Table(filtered, selection: $selection) {
                TableColumn("Date") { s in Text(s.date, format: .dateTime.day().month().year()).monospacedDigit() }.width(100)
                TableColumn("Time") { s in Text(s.date, format: .dateTime.hour().minute().second()).monospacedDigit() }.width(85)
                TableColumn("Conversation") { s in
                    if let url = s.codexURL {
                        Link(s.title, destination: url).lineLimit(2).help("Open in Codex: \(s.title)")
                    } else { Text(s.title).lineLimit(2).help(s.title) }
                }.width(min: 160, ideal: 280)
                TableColumn("Model") { s in Text(s.models.isEmpty ? "—" : s.models.joined(separator: ", ")).help(s.models.joined(separator: ", ")) }.width(145)
                TableColumn("Estimated cost") { s in Text(dollars(store.estimate(s).cost)).monospacedDigit().help(store.estimate(s).reason ?? "Standard API equivalent") }.width(105)
                TableColumn("") { s in Button { detail = s } label: { Image(systemName: "info.circle") }.buttonStyle(.borderless).accessibilityLabel("Details for \(s.title)") }.width(30)
            }
            if filtered.isEmpty { Text("No conversations in this date range.").foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 8) }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Local observed history · May be incomplete").foregroundStyle(.secondary)
                    Button("History details") { historyOpen = true }
                        .popover(isPresented: $historyOpen) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Observed history").font(.headline)
                                Text(store.historySummary)
                                Text("These are observation checkpoints, not proof of complete activity. Sessions created and removed between checks or while the app was closed may be absent. Retained snapshots use current prices.")
                                ScrollView {
                                    ForEach(Array(store.observationPeriods.enumerated()), id: \.offset) { _, period in
                                        Text("\(period.start.formatted(date: .abbreviated, time: .standard)) – \(period.lastCheck.formatted(date: .abbreviated, time: .standard))")
                                    }
                                }.frame(maxHeight: 120)
                                Button("Clear retained history…", role: .destructive) { clearHistory = true }
                            }.font(.caption).padding().frame(width: 360)
                        }
                }
                HStack {
                    Link(destination: URL(string: "https://tools.pwa.ovh/openai-pricing")!) {
                        if let date = store.catalog.flatMap({ parseDate($0.fetchedAt) }) {
                            Text("Prices retrieved \(date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute().second().locale(Locale.autoupdatingCurrent))) (via tools.pwa.ovh) ↗")
                        } else { Text("No prices available (via tools.pwa.ovh) ↗") }
                    }
                    Spacer()
                    Text(store.fetching ? "Updating prices…" : (store.watching ? "Live filesystem events · Prices every 6 h" : "Recovery scan every 60 s · Prices every 6 h")).foregroundStyle(.secondary)
                }
                Text("Estimate convention: total input per request, including cached tokens, determines the context tier; selected rates apply to the entire request. These rules remain unverified by the endpoint.").foregroundStyle(.secondary)
                Text("Excludes tools, subagents and surcharges. Total excludes unavailable estimates. Logs stay on your Mac.").foregroundStyle(.secondary)
                Text("Coverage: local Codex session files only. Work conversations are not covered. A missing conversation does not mean zero usage.").foregroundStyle(.secondary)
                if !store.networkStatus.isEmpty { Text(store.networkStatus).foregroundStyle(.orange) }
                if !store.logStatus.isEmpty { Text(store.logStatus).foregroundStyle(.orange).textSelection(.enabled) }
            }.font(.caption).padding(14)
        }
        .sheet(item: $detail) { session in
            DetailView(session: store.sessions.first(where: { $0.id == session.id }) ?? session, catalog: store.catalog)
        }
        .confirmationDialog("Clear retained history?", isPresented: $clearHistory) {
            Button("Clear retained history", role: .destructive) {
                historyOpen = false
                Task { await store.clearHistory() }
            }
        } message: {
            Text("Removes retained snapshots and observation periods. Currently readable logs will be observed again. Codex source files are never changed.")
        }
    }
}
struct DetailView: View {
    let session: Session
    let catalog: Catalog?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text(session.title).font(.title2.bold()); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
                HStack {
                    Text(session.id).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Button("Copy ID") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.id, forType: .string)
                    }.accessibilityLabel("Copy conversation ID")
                }
                Text(session.models.joined(separator: ", ")).foregroundStyle(.secondary)
                Text(session.sourceAvailable ? "Source available at the latest check" : "Retained snapshot · Source not readable at the latest check")
                    .font(.caption).foregroundStyle(.secondary)
                let estimate = session.estimate(catalog)
                Text(dollars(estimate.cost)).font(.largeTitle.monospacedDigit())
                if let reason = estimate.reason { Label(reason, systemImage: "info.circle").foregroundStyle(.orange) }
                Grid(alignment: .leading, horizontalSpacing: 35, verticalSpacing: 9) {
                    row("Total input (including cache)", session.usage.input)
                    row("Cached input (read)", session.usage.cache)
                    row("Cache writes", session.usage.write)
                    row("Ordinary input", session.usage.input-session.usage.cache-session.usage.write)
                    row("Output, including reasoning", session.usage.output)
                    row("Of which reasoning (do not add)", session.usage.reasoning)
                    row("Usable requests", Int64(session.calls.count))
                }
                if !estimate.context.isEmpty { Text(estimate.context).font(.headline) }
                if session.models.count == 1, let model = catalog?.pricing["standard"]?[session.models[0]] {
                    if let rates = model.unspecifiedContext { priceBlock("Published Standard rates", rates) }
                    if let rates = model.shortContext { priceBlock("Short context (≤ \(model.contextSelection.inputTokenThreshold ?? 0) input tokens)", rates) }
                    if let rates = model.longContext { priceBlock("Long context", rates) }
                }
                Text("Estimates sum cumulative-counter deltas, checked against each request. A partial line is read again after the file changes. An ongoing response is included only after Codex records its usage.").font(.caption).foregroundStyle(.secondary)
                Button("Show log in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.file]) }
                    .disabled(!session.sourceAvailable)
            }.padding(24)
        }.frame(width: 660, height: 650)
    }
    func row(_ title: String, _ value: Int64) -> some View {
        GridRow { Text(title); Text(value.formatted(.number.locale(Locale.autoupdatingCurrent))).monospacedDigit() }
    }
    func priceBlock(_ title: String, _ rates: Rates) -> some View {
        let labels = ["Input", "Cached input", "Output", "Cache write · 30 min", "Cache write · 12 h"]
        let prices = [rates.input, rates.cachedInput, rates.output, rates.cacheWriteWith30MinuteRetention, rates.cacheWriteWith12HourRetention]
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            ForEach(labels.indices, id: \.self) { i in
                HStack {
                    Text(labels[i]); Spacer()
                    Text(prices[i].map { ($0.priceInMicrodollars / $0.microdollarsPerDollar).formatted(.number.locale(.autoupdatingCurrent)) + " USD / 1 M tokens" } ?? "Unknown")
                }
            }
        }.font(.caption).padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
