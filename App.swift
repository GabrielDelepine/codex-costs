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
    var fetching = false
    var watching = false
    var updateStatus: String {
        if fetching { return "Updating prices…" }
        let updates = watching
            ? (windowVisible ? "Live filesystem events" : "Filesystem events batched over 30 s")
            : "Recovery scan every 60 s"
        return updates + " · Prices every 6 h"
    }
    private var watcher: LogWatcher?
    private let logs = SessionCache()
    private(set) var windowVisible = false
    private var scanning = false
    private var rescanPending = false
    private var running = false
    private var monitoring: Task<Void, Never>?
    private var lastAttempt = Date.distantPast
    private let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodexCosts/pricing.json")
    init() {
        if let data = try? Data(contentsOf: cache) { catalog = try? Catalog.decode(data) }
    }
    func estimate(_ session: Session) -> Estimate {
        estimates[session.id] ?? .unavailable("Usage not processed yet")
    }
    private func updateEstimates(changedIDs: Set<String>? = nil) {
        estimates = Dictionary(sessions.map { session in
            let previous = changedIDs?.contains(session.id) == false ? estimates[session.id] : nil
            return (session.id, previous ?? session.estimate(catalog))
        }, uniquingKeysWith: { _, new in new })
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
        var updatedIDs = Set<String>()
        repeat {
            rescanPending = false
            if followToday && range != .today { range = .today }
            let selected = range
            let result = await logs.scan(folders: selected.folders(root: Logs.root))
            updatedIDs.formUnion(result.updatedSessionIDs)
            let days = await logs.conversationDays()
            if days != availableDays { availableDays = days }
            if range == selected {
                if result.changed { sessions = result.sessions; updateEstimates(changedIDs: updatedIDs) }
                updatedIDs.removeAll()
                logStatus = result.errors.joined(separator: "\n")
            } else { rescanPending = true }
        } while rescanPending && !Task.isCancelled
        scanning = false
    }
    func filesChanged() {
        // FSEvents already batches writes. Never postpone a scan for a quiet period.
        Task { await scan() }
    }
    func updateWindowVisibility(excluding closingWindow: NSWindow? = nil) {
        let visible = !NSApp.isHidden && NSApp.windows.contains {
            $0 !== closingWindow && $0.canBecomeMain && $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        }
        guard visible != windowVisible else { return }
        windowVisible = visible
        if running { configureWatcher() }
        if visible { wake() }
        else if running { Task { await scan() } }
    }
    private func configureWatcher() {
        // Start the new stream before checking logs, covering writes during the transition.
        watcher = LogWatcher(root: Logs.root, latency: windowVisible ? 0.4 : 30) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.filesChanged()
            }
        }
        watching = watcher?.isRunning == true
    }
    func wake() {
        Task { await scan() }
        Task { await refreshPrices() }
    }
    func start() {
        guard monitoring == nil else { return }
        // Monitoring belongs to the app, not to the first window that happened to open.
        monitoring = Task { await run() }
    }
    func run() async {
        guard !running else { return }; running = true
        let visibilityNotifications = [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
                                       NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                                       NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                                       NSApplication.didBecomeActiveNotification]
        let observers = visibilityNotifications.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let closing = name == NSWindow.willCloseNotification ? notification.object as? NSWindow : nil
                Task { @MainActor [weak self] in self?.updateWindowVisibility(excluding: closing) }
            }
        }
        let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.wake() }
        }
        updateWindowVisibility()
        if watcher == nil { configureWatcher() }
        defer {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            watcher = nil; watching = false; running = false
        }
        await scan()
        Task { await refreshPrices() }
        // Recovery for missed events, sleep, missing folders, midnight and pricing deadlines.
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            if !watching { configureWatcher() }
            await scan()
            Task { await refreshPrices() }
        }
    }
}

@main struct CodexCostsApp: App {
    @State private var store = Store()
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        WindowGroup {
            MainView(store: store)
                .environment(\.locale, Locale.autoupdatingCurrent)
                .frame(minWidth: 1020, minHeight: 520)
                .task { store.start() }
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); store.updateWindowVisibility() }
        }.defaultSize(width: 1220, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Codex Costs") { openWindow(id: "about") }
            }
        }
        Window("About Codex Costs", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
struct AboutView: View {
    private let metadata = Bundle.main.infoDictionary ?? [:]

    private func value(_ key: String) -> String {
        metadata[key] as? String ?? ""
    }

    private func timestamp(_ key: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value(key)) else { return "Unavailable" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return "\(formatter.string(from: date)) (\(formatter.timeZone.abbreviation(for: date) ?? formatter.timeZone.identifier))"
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Codex Costs").font(.system(size: 22, weight: .semibold))
                    Text("Version \(value("CFBundleShortVersionString"))")
                        .font(.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Text("Commit").foregroundStyle(.secondary)
                    if value("CodexCommitHash").count == 40,
                       value("CodexCommitHash").allSatisfy({ $0.isHexDigit }),
                       let url = URL(string: "https://github.com/GabrielDelepine/codex-costs/commit/\(value("CodexCommitHash"))") {
                        Link(String(value("CodexCommitHash").prefix(7)), destination: url)
                            .help(value("CodexCommitHash"))
                            .accessibilityLabel("View commit \(value("CodexCommitHash")) on GitHub")
                    } else {
                        Text("Unavailable")
                    }
                }
                GridRow { Text("Commit date").foregroundStyle(.secondary); Text(timestamp("CodexCommitDate")) }
                GridRow { Text("Built").foregroundStyle(.secondary); Text(timestamp("CodexBuildDate")) }
            }
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            if value("CodexSourceState") == "Modified" {
                Text("Built with local changes; the commit links to the base source.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(width: 384)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MainView: View {
    @Bindable var store: Store
    @State private var selection: String?
    @State private var detail: Session?
    @State private var search = ""
    @State private var calendarOpen = false
    @State private var draft = DayRange.today
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
                    .help("Selects today now and follows day changes at the next log check, including when a window becomes visible again or the Mac wakes. Choosing dates turns this off. Enabled on each app launch. Usage updates in either mode.")
                Spacer()
                TextField("Search title, ID or model", text: $search).textFieldStyle(.roundedBorder).frame(width: 240)
                Button {
                    Task { await store.scan() }
                    Task { await store.refreshPrices(force: true) }
                } label: { Image(systemName: "arrow.clockwise") }.help("Check logs and refresh prices")
                    .disabled(store.fetching)
            }.padding(.horizontal, 20).padding(.bottom, 14)
            Text("Usage updates for any selected dates. Auto-select today follows the current day; choosing dates turns it off. Enabled on each launch.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20).padding(.bottom, 10)
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
                    Link(destination: URL(string: "https://tools.pwa.ovh/openai-pricing")!) {
                        if let date = store.catalog.flatMap({ parseDate($0.fetchedAt) }) {
                            Text("Prices retrieved \(date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute().second().locale(Locale.autoupdatingCurrent))) (via tools.pwa.ovh) ↗")
                        } else { Text("No prices available (via tools.pwa.ovh) ↗") }
                    }
                    Spacer()
                    Text(store.updateStatus).foregroundStyle(.secondary)
                }
                Text("Estimate convention: total input per request, including cached tokens, determines the context tier; selected rates apply to the entire request. These rules remain unverified by the endpoint.").foregroundStyle(.secondary)
                Text("Excludes tools, subagents and surcharges. Total excludes unavailable estimates. Logs stay on your Mac.").foregroundStyle(.secondary)
                if !store.networkStatus.isEmpty { Text(store.networkStatus).foregroundStyle(.orange) }
                if !store.logStatus.isEmpty { Text(store.logStatus).foregroundStyle(.orange).textSelection(.enabled) }
            }.font(.caption).padding(14)
        }
        .sheet(item: $detail) { session in
            DetailView(session: store.sessions.first(where: { $0.id == session.id }) ?? session, catalog: store.catalog)
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
                let breakdowns = session.pricingBreakdowns(catalog)
                if breakdowns.isEmpty {
                    Text("No pricing applied: no request estimate is available.").font(.caption).foregroundStyle(.secondary)
                } else {
                    if estimate.cost == nil {
                        Text("Pricing below applies only to available request estimates; the conversation estimate is unavailable.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(breakdowns, id: \.id) { applied in AppliedPricingView(applied: applied, showModel: session.models.count > 1) }
                }
                Text("Estimates sum cumulative-counter deltas, checked against each request. A partial line is read again after the file changes. An ongoing response is included only after Codex records its usage.").font(.caption).foregroundStyle(.secondary)
                Button("Show log in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.file]) }
            }.padding(24)
        }.frame(width: 660, height: 650)
    }
    func row(_ title: String, _ value: Int64) -> some View {
        GridRow { Text(title); Text(value.formatted(.number.locale(Locale.autoupdatingCurrent))).monospacedDigit() }
    }
}

struct AppliedPricingView: View {
    let applied: PricingBreakdown
    let showModel: Bool
    private let labels = ["Ordinary input", "Cached input", "Output (including reasoning)", "Cache write · 30 min", "Cache write · 12 h"]
    var body: some View {
        let rates = applied.rates
        let prices = [rates.input, rates.cachedInput, rates.output, rates.cacheWriteWith30MinuteRetention, rates.cacheWriteWith12HourRetention]
        VStack(alignment: .leading, spacing: 6) {
            Text("Applied pricing: \(applied.context)").font(.headline)
            if showModel { Text(applied.model).foregroundStyle(.secondary) }
            ForEach(labels.indices, id: \.self) { i in
                HStack {
                    Image(systemName: applied.used[i] ? "checkmark.square" : "square")
                        .accessibilityLabel(applied.used[i] ? "Applied" : "Not applied")
                    Text(labels[i])
                    Spacer()
                    Text(prices[i].flatMap { price in
                        (try? price.cost(1_000_000)).map {
                            $0.formatted(.number.precision(.fractionLength(0...8)).locale(.autoupdatingCurrent)) + " " + price.currency + " / 1 M tokens"
                        }
                    } ?? "Unknown")
                }.accessibilityElement(children: .combine)
            }
            Text("Checked means this rate contributed tokens to an available estimate. Unchecked means it was not used.")
                .foregroundStyle(.secondary)
        }.font(.caption).padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
