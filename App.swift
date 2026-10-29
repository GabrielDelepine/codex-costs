import SwiftUI
import AppKit
import Observation

@MainActor @Observable final class Store {
    let releases = ReleaseUpdates()
    var range = DayRange.today
    var followToday = true
    var availableDays: Set<Date> = []
    var sessions: [Session] = []
    var allSessions: [Session] = []
    private var appliedRange: DayRange?
    private var appliedTimeZone = TimeZone.current
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
            let zone = TimeZone.current
            let scopeChanged = appliedRange != selected || appliedTimeZone != zone
            let result = await logs.scan()
            updatedIDs.formUnion(result.updatedSessionIDs)
            let days = Set(result.sessions.flatMap { $0.calls.compactMap(\.timestamp) }.map { Calendar.current.startOfDay(for: $0) })
            if days != availableDays { availableDays = days }
            if range == selected && TimeZone.current == zone {
                if result.changed || scopeChanged {
                    allSessions = result.sessions
                    sessions = result.sessions.map { $0.scoped(to: selected) }
                        .filter { !$0.calls.isEmpty }
                        .sorted { ($0.firstActivity ?? .distantPast) < ($1.firstActivity ?? .distantPast) }
                    updateEstimates(changedIDs: scopeChanged ? nil : updatedIDs)
                    appliedRange = selected; appliedTimeZone = zone
                }
                updatedIDs.removeAll()
                let incomplete = result.sessions.filter { !$0.issues.isEmpty }.count
                let warnings = incomplete > 0 ? ["Incomplete usage coverage in \(incomplete.formatted()) conversations. Period estimates may be unavailable; only validated requests are listed."] : []
                logStatus = (result.errors + warnings).joined(separator: "\n")
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
        Task { await releases.check() }
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
        Task { await releases.check() }
        // Recovery for missed events, sleep, missing folders, midnight and pricing deadlines.
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            if !watching { configureWatcher() }
            await scan()
            Task { await refreshPrices() }
            Task { await releases.check() }
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
                .frame(minWidth: 640, minHeight: 520)
                .task { store.start() }
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); store.updateWindowVisibility() }
        }.defaultSize(width: 1220, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Codex Costs") { openWindow(id: "about") }
                Button(store.releases.checking ? "Checking for Updates…" : "Check for Updates…") {
                    openWindow(id: "updates")
                    Task { await store.releases.check(manual: true) }
                }.disabled(store.releases.checking)
                Toggle("Automatically Check for Updates", isOn: Binding(
                    get: { store.releases.automaticallyChecks },
                    set: { enabled in
                        store.releases.automaticallyChecks = enabled
                        if enabled { Task { await store.releases.check() } }
                    }))
            }
        }
        Window("Software Update", id: "updates") {
            UpdatesView(updates: store.releases)
        }
        .windowResizability(.contentSize)
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
    @Environment(\.openWindow) private var openWindow
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
        GeometryReader { geometry in content(compact: geometry.size.width < 900) }
            .sheet(item: $detail) { session in
                DetailView(session: store.allSessions.first(where: { $0.id == session.id }) ?? session,
                           range: store.range, catalog: store.catalog)
            }
    }
    private func content(compact: Bool) -> some View {
        let controlsLayout = compact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout())
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 12) {
                        Text("Codex Costs").font(.title2.bold())
                        if store.releases.updateAvailable {
                            Button {
                                store.releases.showAvailableRelease()
                                openWindow(id: "updates")
                            } label: {
                                Label("Update available", systemImage: "arrow.up.circle.fill")
                            }
                            .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
                            .help("View the available Codex Costs release")
                        }
                    }
                    Text("Token estimates · Current Standard API rates · USD").foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(dollars(total)).font(.title2.monospacedDigit().bold())
                    Text("\(filtered.count - unavailable) estimated · \(unavailable) unavailable").foregroundStyle(.secondary).font(.caption)
                }
            }.padding(20)
            controlsLayout {
                HStack {
                    Button { draft = store.range; calendarOpen = true } label: {
                        Label(store.range.label, systemImage: "calendar")
                    }.popover(isPresented: $calendarOpen, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Select a date").font(.headline)
                            RangeCalendar(range: $draft, availableDays: store.availableDays)
                            Text("Shift-click to select a range. Grey days have no dated usage.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                }
                HStack {
                    TextField("Search title, ID or model", text: $search).textFieldStyle(.roundedBorder)
                        .frame(minWidth: 150, maxWidth: compact ? .infinity : 240)
                    Button {
                        Task { await store.scan() }
                        Task { await store.refreshPrices(force: true) }
                    } label: { Image(systemName: "arrow.clockwise") }.help("Check logs and refresh prices")
                        .disabled(store.fetching)
                }
            }.padding(.horizontal, 20).padding(.bottom, 14)
            Text("Selected period · " + store.range.label + " · Requests are counted on their recorded local day.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20).padding(.bottom, 10)
            Divider()
            if compact {
                Table(filtered, selection: $selection) { sessionColumns(compact: true) }
            } else {
                Table(filtered, selection: $selection) {
                    TableColumn("Activity date") { s in Text(s.firstActivity.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unknown").monospacedDigit() }.width(100)
                    TableColumn("First usage") { s in Text(s.firstActivity.map { $0.formatted(date: .omitted, time: .standard) } ?? "—").monospacedDigit() }.width(85)
                    sessionColumns(compact: false)
                }
            }
            if filtered.isEmpty { Text("No recorded usage in this selection.").foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 8) }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                controlsLayout {
                    Link(destination: URL(string: "https://tools.pwa.ovh/openai-pricing")!) {
                        if let date = store.catalog.flatMap({ parseDate($0.fetchedAt) }) {
                            Text("Prices retrieved \(date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute().second().locale(Locale.autoupdatingCurrent))) (via tools.pwa.ovh) ↗")
                        } else { Text("No prices available (via tools.pwa.ovh) ↗") }
                    }
                    if !compact { Spacer() }
                    Text(store.updateStatus).foregroundStyle(.secondary)
                }
                Text("Estimate convention: total input per request, including cached tokens, determines the context tier; selected rates apply to the entire request. These rules remain unverified by the endpoint.").foregroundStyle(.secondary)
                Text("Excludes tools, subagents and surcharges. Total excludes unavailable estimates. Logs stay on your Mac.").foregroundStyle(.secondary)
                if !store.networkStatus.isEmpty { Text(store.networkStatus).foregroundStyle(.orange) }
                if !store.logStatus.isEmpty { Text(store.logStatus).foregroundStyle(.orange).textSelection(.enabled) }
            }.font(.caption).padding(14)
        }
    }
    @TableColumnBuilder<Session, Never>
    private func sessionColumns(compact: Bool) -> some TableColumnContent<Session, Never> {
        TableColumn("Conversation") { s in
            VStack(alignment: .leading, spacing: 3) {
                if let url = s.codexURL {
                    Link(destination: url) {
                        Text(s.title).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.help("Open in Codex: \(s.title)")
                } else { Text(s.title).lineLimit(1).truncationMode(.tail).help(s.title) }
                if compact {
                    Text(s.firstActivity.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "Date unknown")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.width(min: compact ? 120 : 160, ideal: 280, max: .infinity)
        TableColumn("Model") { s in
            Text(s.models.isEmpty ? "—" : s.models.joined(separator: ", "))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(s.models.joined(separator: ", "))
        }.width(145)
        TableColumn("Estimated cost") { s in Text(dollars(store.estimate(s).cost)).monospacedDigit().help(store.estimate(s).reason ?? "Standard API equivalent") }.width(90)
        TableColumn("") { s in Button { detail = s } label: { Image(systemName: "info.circle") }.buttonStyle(.borderless).accessibilityLabel("Details for \(s.title)") }.width(compact ? 24 : 30)
    }

}
struct DetailView: View {
    let session: Session
    let range: DayRange
    let catalog: Catalog?
    @State private var entireConversation = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollViewReader { scroll in
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
                    let scoped = session.scoped(to: range)
                    let identicalScopes = scoped.calls.count == session.calls.count
                    let showingEntireConversation = entireConversation || identicalScopes
                    let displayed = showingEntireConversation ? session : scoped
                    let estimate = scoped.estimate(catalog)
                    let entireEstimate = session.estimate(catalog)
                    HStack(alignment: .top, spacing: 12) {
                        if !identicalScopes {
                            summary("Selected period", dates: range.label, estimate: estimate, count: scoped.calls.count, highlighted: !showingEntireConversation) { entireConversation = false }
                        }
                        summary("Entire conversation", dates: session.activityRange?.label ?? "No dated activity", estimate: entireEstimate, count: session.calls.count, highlighted: showingEntireConversation) { entireConversation = true }
                    }
                    Text(showingEntireConversation ? "Details · Entire conversation" : "Details · Selected period · " + range.label)
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Created " + session.date.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 35, verticalSpacing: 9) {
                        row("Total input (including cache)", displayed.usage.input)
                        row("Cached input (read)", displayed.usage.cache)
                        row("Cache writes", displayed.usage.write)
                        row("Ordinary input", displayed.usage.input-displayed.usage.cache-displayed.usage.write)
                        row("Output, including reasoning", displayed.usage.output)
                        row("Of which reasoning (do not add)", displayed.usage.reasoning)
                        row("Usable requests", Int64(displayed.calls.count))
                    }
                    let breakdowns = displayed.pricingBreakdowns(catalog)
                    if breakdowns.isEmpty {
                        Text("No pricing applied: no request estimate is available.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        if (showingEntireConversation ? entireEstimate : estimate).cost == nil {
                            Text("Pricing below applies only to available request estimates; the estimate for this scope is unavailable.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(breakdowns, id: \.id) { applied in AppliedPricingView(applied: applied, showModel: session.models.count > 1) }
                    }
                    Text("Estimates sum cumulative-counter deltas, checked against each request. A partial line is read again after the file changes. An ongoing response is included only after Codex records its usage.").font(.caption).foregroundStyle(.secondary)
                    Button("Show log in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.file]) }
                    Divider()
                    RequestTable(session: session, range: range, catalog: catalog, scroll: scroll, entireConversation: showingEntireConversation)
                        .id(showingEntireConversation)
                }.padding(24)
            }.frame(width: 660, height: 650)
        }
    }
    private func summary(_ title: String, dates: String, estimate: Estimate, count: Int, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(dates).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text(dollars(estimate.cost)).font(.title.monospacedDigit().weight(highlighted ? .bold : .regular))
                Text("\(count.formatted()) \(count == 1 ? "request" : "requests")").monospacedDigit()
                if let reason = estimate.reason { Text(reason).font(.caption).foregroundStyle(.orange) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(highlighted ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(highlighted ? Color.accentColor : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
        .help("Show tokens, applied pricing and requests for " + title.lowercased())
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

struct RequestRow: Identifiable {
    let id: Int
    let call: Call
    let estimate: Estimate
    let costs: RequestCostBreakdown?
    let context: String
    init(index: Int, call: Call, catalog: Catalog?) {
        id = index + 1
        self.call = call
        estimate = call.estimate(catalog)
        costs = try? call.costBreakdown(catalog)
        context = (try? call.appliedPricing(catalog).context) ?? "Unavailable"
    }
}

struct RequestTable: View {
    let session: Session
    let range: DayRange
    let catalog: Catalog?
    let scroll: ScrollViewProxy
    let entireConversation: Bool
    var body: some View {
        let allRows = session.calls.enumerated().map { RequestRow(index: $0.offset, call: $0.element, catalog: catalog) }
        let datedRows = allRows.filter { $0.call.timestamp != nil }
        let rows = entireConversation ? datedRows : datedRows.filter { $0.call.timestamp.map { range.contains($0) } ?? false }
        let undatedRows = allRows.filter { $0.call.timestamp == nil }
        VStack(alignment: .leading, spacing: 10) {
            Text("Individual requests").font(.headline)
            Text(entireConversation ? "Entire conversation" : "Selected period · " + range.label)
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Showing \(rows.count.formatted()) of \(datedRows.count.formatted()) dated requests · in log order. Select a row to inspect its token counters.")
                .font(.caption).foregroundStyle(.secondary)
            if !session.issues.isEmpty {
                Text("Incomplete coverage: \(session.issues.joined(separator: " · ")). Only validated requests are listed.")
                    .font(.caption).foregroundStyle(.orange)
            }
            RequestList(rows: rows, label: "Dated requests", scroll: scroll)
            if !undatedRows.isEmpty {
                Divider()
                Text("Undated requests (\(undatedRows.count.formatted()))").font(.headline)
                Text("These requests are undated, but belong to this conversation. They are excluded from daily and period totals.")
                    .font(.caption).foregroundStyle(.secondary)
                RequestList(rows: undatedRows, label: "Undated requests", scroll: scroll)
            }
            Text("Dates and times are usage-event timestamps in the local time zone, not request start times. Usage crossing midnight belongs to the recorded event day. Input includes cache; output includes reasoning. Repeated unchanged events are excluded.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct RequestList: View {
    let rows: [RequestRow]
    let label: String
    let scroll: ScrollViewProxy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rows.isEmpty {
                Text("No dated requests in this selection.").foregroundStyle(.secondary)
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("#") { row in Text(row.id.formatted()) }.width(24)
                    TableColumn("Date") { row in
                        Text(row.call.timestamp.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unknown")
                            .help(row.call.timestamp.map { $0.formatted(date: .complete, time: .standard) } ?? "Timestamp not recorded")
                    }.width(85)
                    TableColumn("Time") { row in
                        Text(row.call.timestamp.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
                            .help(row.call.timestamp.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "Timestamp not recorded")
                    }.width(72)
                    TableColumn("Model") { row in
                        Text(row.call.model ?? "Not recorded").lineLimit(1).help(row.call.model ?? "Model not recorded")
                    }.width(min: 65, ideal: 85, max: .infinity)
                    TableColumn("Context") { row in
                        Text(row.context == "Published rates without a context threshold" ? "Unspecified" : row.context)
                            .lineLimit(1).help(row.context)
                    }.width(105)
                    TableColumn("Estimated cost") { row in
                        Text(dollars(row.estimate.cost)).help(row.estimate.reason ?? "Standard API equivalent")
                    }.width(90)
                }
                .monospacedDigit()
                .frame(height: CGFloat(min(rows.count, 7)) * 28 + 48)
                .accessibilityLabel(label)
                if let selected = rows.first(where: { $0.id == selection }) {
                    RequestDetails(row: selected)
                        .id("request-details-" + label)
                        .task(id: selected.id) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                scroll.scrollTo("request-details-" + label, anchor: .bottom)
                            }
                        }
                }
            }
        }
        .onChange(of: rows.map(\.id)) { _, _ in selection = nil }
    }
}

struct RequestDetails: View {
    let row: RequestRow
    var body: some View {
        let usage = row.call.usage
        VStack(alignment: .leading, spacing: 8) {
            Text("Request \(row.id)").font(.subheadline.bold())
            Text(row.call.timestamp.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "Timestamp not recorded")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 5) {
                GridRow { Text("Total input (including cache)"); Text(row.call.usage.input.formatted()) }
                GridRow { Text("Cached input (read)"); Text(row.call.usage.cache.formatted()) }
                GridRow { Text("Cache writes"); Text(row.call.usage.write.formatted()) }
                GridRow { Text("Input excluding cache"); Text(usage.isConsistent ? (usage.input-usage.cache-usage.write).formatted() : "—") }
                GridRow {
                    Text("Cached share of total input")
                    Text(usage.isConsistent && usage.input > 0
                         ? (Double(usage.cache) / Double(usage.input)).formatted(.percent.precision(.fractionLength(1)).locale(.autoupdatingCurrent)) : "—")
                }
                GridRow { Text("Output (including reasoning)"); Text(row.call.usage.output.formatted()) }
                GridRow { Text("Of which reasoning (do not add)"); Text(usage.reasoning.formatted()) }
                GridRow { Text("Output excluding reasoning"); Text(usage.isConsistent ? (usage.output-usage.reasoning).formatted() : "—") }
            }.monospacedDigit()
            Divider()
            Text("Estimated cost by component").font(.subheadline.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 5) {
                GridRow { Text("Input excluding cache"); Text(dollars(row.costs?.ordinaryInput)) }
                GridRow { Text("Cached input (read)"); Text(dollars(row.costs?.cachedInput)) }
                GridRow { Text("Output (including reasoning)"); Text(dollars(row.costs?.output)) }
                if usage.write > 0 { GridRow { Text("Cache writes"); Text("Unavailable: retention unknown") } }
                GridRow { Text("Total").bold(); Text(dollars(row.estimate.cost)).bold() }
            }.monospacedDigit()
            Text("Components use the request’s context tier and current Standard rates. Rounded components may not sum to the displayed total.")
                .foregroundStyle(.secondary)
            if let reason = row.estimate.reason { Text(reason).foregroundStyle(.orange) }
        }
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
