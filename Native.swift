import SwiftUI
import AppKit
import CoreServices

// Crisp SwiftUI date cells: AppKit's mini calendar cannot disable individual days.
struct RangeCalendar: View {
    @Binding var range: DayRange
    let availableDays: Set<Date>
    @State private var month: Date
    @State private var anchor: Date?
    private let calendar = Calendar.current
    init(range: Binding<DayRange>, availableDays: Set<Date>) {
        _range = range
        self.availableDays = availableDays
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: range.wrappedValue.end)!.start)
    }
    private var dates: [Date] {
        let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)!.count
        let cells = ((offset + count + 6) / 7) * 7
        return (0..<cells).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: month) }
    }
    private var monthLabel: String {
        let f = DateFormatter(); f.locale = .autoupdatingCurrent; f.setLocalizedDateFormatFromTemplate("MMM yyyy")
        return f.string(from: month)
    }
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 5) {
                Text(monthLabel).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button { move(-1) } label: { Image(systemName: "chevron.left") }.help("Previous month")
                Button { month = calendar.dateInterval(of: .month, for: Date())!.start } label: { Image(systemName: "circle.fill").font(.system(size: 6)) }.help("Current month")
                Button { move(1) } label: { Image(systemName: "chevron.right") }.help("Next month")
                    .disabled(month >= calendar.dateInterval(of: .month, for: Date())!.start)
            }.buttonStyle(.borderless).font(.system(size: 10))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 0), count: 7), spacing: 2) {
                ForEach(Array((0..<7).map { calendar.veryShortStandaloneWeekdaySymbols[($0 + calendar.firstWeekday - 1) % 7] }.enumerated()), id: \.offset) { _, day in
                    Text(day).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).frame(width: 24, height: 16)
                }
                ForEach(dates, id: \.self) { date in
                    let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                    let enabled = inMonth && date <= calendar.startOfDay(for: Date()) && availableDays.contains(date)
                    let selected = enabled && (date == range.start || date == range.end)
                    let inside = inMonth && range.start < date && date < range.end
                    Button {
                        if NSEvent.modifierFlags.contains(.shift) { range = DayRange(anchor ?? range.start, date) }
                        else { anchor = date; range = DayRange(date, date) }
                    } label: {
                        Text(calendar.component(.day, from: date).formatted(.number.grouping(.never).locale(.autoupdatingCurrent)))
                            .font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(selected ? Color.white : (enabled ? Color.primary : Color.secondary.opacity(inMonth ? 0.4 : 0.2)))
                            .frame(width: 24, height: 22)
                            .background(selected ? Color.accentColor : (inside ? Color.accentColor.opacity(0.1) : Color.clear), in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!enabled)
                        .help(enabled ? "Select date; Shift-click to extend the selection" : "No conversations available")
                        .accessibilityLabel(date.formatted(.dateTime.month().day().year().locale(Locale.autoupdatingCurrent)))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }.frame(width: 168)
    }
    private func move(_ delta: Int) {
        if let date = calendar.date(byAdding: .month, value: delta, to: month) { month = date }
    }
}

private final class EventRelay {
    let root: String
    let handler: () -> Void
    init(root: String, handler: @escaping () -> Void) { self.root = root; self.handler = handler }
    func receive(paths: [String], flags: UnsafePointer<FSEventStreamEventFlags>, count: Int) {
        let sessions = root + "/sessions"
        let archives = root + "/archived_sessions"
        let index = root + "/session_index.jsonl"
        for i in 0..<count {
            let recovery = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)
            if flags[i] & recovery != 0 { handler(); return }
        }
        // Ignore pricing downloads, SQLite writes and other unrelated .codex files.
        if paths.contains(where: { $0 == root || $0 == index || $0 == sessions || $0.hasPrefix(sessions + "/") || $0 == archives || $0.hasPrefix(archives + "/") }) { handler() }
    }
}
final class LogWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "ovh.pwa.codex-costs.events", qos: .utility)
    init(root: URL, latency: CFTimeInterval, onChange: @escaping () -> Void) {
        let relay = EventRelay(root: root.path, handler: onChange)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(relay).toOpaque(), retain: { info in
            guard let info else { return nil }
            return UnsafeRawPointer(Unmanaged<EventRelay>.fromOpaque(info).retain().toOpaque())
        }, release: { info in
            if let info { Unmanaged<EventRelay>.fromOpaque(info).release() }
        }, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        stream = FSEventStreamCreate(nil, { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let relay = Unmanaged<EventRelay>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
            relay.receive(paths: paths, flags: flags, count: count)
        }, &context, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            if !FSEventStreamStart(stream) { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); self.stream = nil }
        }
    }
    var isRunning: Bool { stream != nil }
    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
