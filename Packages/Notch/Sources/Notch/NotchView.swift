import AppKit
import SonaryUI
import SwiftUI

/// The island: a black shape the size of the notch that opens into widget tabs on hover or click.
struct NotchView: View {
    let model: NotchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let expanded = model.presentation == .expanded
        let size = expanded ? NotchModel.expandedSize : model.notchSize
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 22 : 9, bottomTrailingRadius: expanded ? 22 : 9,
                                   style: .continuous)
                .fill(Color.black)
            if expanded {
                expandedContent
                    .padding(.top, model.notchSize.height + 2)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onHover { model.hoverChanged($0) }
        .onTapGesture { model.clicked() }
        .background(ScrollCatcher { deltaX, deltaY in model.scrolled(deltaX: deltaX, deltaY: deltaY) })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(sonaryAnimation(reduceMotion), value: expanded)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Sonary island", bundle: .module))
    }

    @ViewBuilder
    private var expandedContent: some View {
        let widgets = model.settings.widgets
        if widgets.isEmpty {
            Text("Turn on widgets in Sonary's settings.", bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                IconTabBar(
                    tabs: widgets.map { IconTab(id: $0, symbol: $0.symbol, title: Text(widgetTitle($0), bundle: .module)) },
                    selection: Binding(get: { widgets.contains(model.selectedWidget) ? model.selectedWidget : widgets[0] },
                                       set: { model.selectedWidget = $0 })
                )
                Group {
                    switch widgets.contains(model.selectedWidget) ? model.selectedWidget : widgets[0] {
                    case .music: MusicWidget(center: model.music)
                    case .calendar: CalendarWidget(source: model.calendar)
                    case .timer: TimerWidget(model: model)
                    case .downloads: DownloadsWidget(watcher: model.downloads)
                    case .batteries: BatteriesWidget(batteries: model.batteries)
                    case .shelf: ShelfWidget(shelf: model.shelf)
                    case .camera: NotchCameraView(camera: model.camera)
                    case .controls: ControlsWidget(controls: model.controls)
                    case .notes: NotesWidget(controls: model.controls)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

func widgetTitle(_ widget: NotchWidget) -> LocalizedStringKey {
    switch widget {
    case .music: "Music"
    case .calendar: "Calendar"
    case .timer: "Timer"
    case .downloads: "Downloads"
    case .batteries: "Batteries"
    case .shelf: "Shelf"
    case .camera: "Camera"
    case .controls: "Controls"
    case .notes: "Notes"
    }
}

struct EmptyWidget: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        Label { Text(text, bundle: .module) } icon: { Image(systemName: symbol) }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MusicWidget: View {
    let center: NowPlayingCenter

    var body: some View {
        if let track = center.nowPlaying {
            HStack(spacing: 14) {
                Image(systemName: track.player == .spotify ? "music.note.house" : "music.note")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.sonaryAccent)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 14) {
                    control("backward.fill", Text("Previous track", bundle: .module)) { center.previous() }
                    control(track.isPlaying ? "pause.fill" : "play.fill",
                            track.isPlaying ? Text("Pause", bundle: .module) : Text("Play", bundle: .module)) { center.playPause() }
                    control("forward.fill", Text("Next track", bundle: .module)) { center.next() }
                }
            }
        } else {
            EmptyWidget(symbol: "music.note", text: "Nothing is playing")
        }
    }

    private func control(_ symbol: String, _ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct CalendarWidget: View {
    let source: CalendarSource
    @State private var showsMonth = false
    @State private var month = Date()
    @State private var day: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if source.hasAccess {
                Picker(selection: $showsMonth) {
                    Text("Today", bundle: .module).tag(false)
                    Text("Month", bundle: .module).tag(true)
                } label: { EmptyView() }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(width: 140)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if showsMonth, source.hasAccess {
                if let day {
                    dayView(day)
                } else {
                    monthView
                }
            } else {
                today
            }
        }
    }

    private var monthView: some View {
        let calendar = Calendar.current
        let busy = source.eventDays(inMonthOf: month)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return VStack(spacing: 3) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(Text("Previous month", bundle: .module))
                Spacer()
                Text(month, format: .dateTime.month(.wide).year()).font(.caption.weight(.semibold))
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel(Text("Next month", bundle: .module))
            }
            .buttonStyle(.plain)
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(monthGrid(for: month).enumerated()), id: \.offset) { _, date in
                    if let date {
                        let number = calendar.component(.day, from: date)
                        Button { day = date } label: {
                            VStack(spacing: 0) {
                                Text(verbatim: "\(number)")
                                    .font(.system(size: 10, weight: calendar.isDateInToday(date) ? .bold : .regular))
                                    .foregroundStyle(calendar.isDateInToday(date) ? Color.sonaryAccent : .primary)
                                Circle().fill(busy.contains(number) ? Color.sonaryAccent : .clear).frame(width: 3, height: 3)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 12)
                    }
                }
            }
        }
    }

    private func dayView(_ date: Date) -> some View {
        let items = source.events(on: date)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { day = nil } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Back to the month", bundle: .module))
                Text(date, format: .dateTime.weekday(.wide).day().month()).font(.caption.weight(.semibold))
            }
            if items.isEmpty {
                Text("Nothing on that day", bundle: .module).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(items.prefix(5)) { item in eventRow(item) }
        }
    }

    private func shiftMonth(_ months: Int) {
        month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
    }

    private func eventRow(_ item: CalendarItem) -> some View {
        HStack(spacing: 10) {
            if item.isAllDay {
                Text("All day", bundle: .module).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
            } else {
                Text(item.start, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
            }
            Text(item.title).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var today: some View {
        if !source.hasAccess {
            VStack(spacing: 8) {
                Text("Sonary needs access to your calendars.", bundle: .module).font(.callout).foregroundStyle(.secondary)
                Button { Task { await source.requestAccess() } } label: { Text("Allow access", bundle: .module) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if source.items.isEmpty {
            EmptyWidget(symbol: "calendar", text: "No more events today")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(source.items) { item in eventRow(item) }
            }
            .onAppear { source.refresh() }
        }
    }
}

private struct TimerWidget: View {
    let model: NotchModel

    var body: some View {
        if model.timer.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    Text(formatCountdown(model.timer.remaining(at: context.date)))
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Spacer()
                    Button(role: .cancel) { model.cancelTimer() } label: { Text("Stop", bundle: .module) }
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach([1, 5, 10, 25], id: \.self) { minutes in
                    Button { model.startTimer(minutes: minutes) } label: {
                        Text("\(minutes) min", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct DownloadsWidget: View {
    let watcher: DownloadsWatcher

    var body: some View {
        if watcher.entries.isEmpty {
            EmptyWidget(symbol: "arrow.down.circle", text: "No recent downloads")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(watcher.entries) { entry in
                    Button {
                        NSWorkspace.shared.open(entry.url)
                    } label: {
                        VStack(spacing: 4) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                                .resizable().frame(width: 32, height: 32)
                            Text(entry.url.lastPathComponent).font(.caption2).lineLimit(1).truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .onDrag { NSItemProvider(contentsOf: entry.url) ?? NSItemProvider() }
                }
            }
        }
    }
}

private struct BatteriesWidget: View {
    let batteries: [AccessoryBattery]

    var body: some View {
        if batteries.isEmpty {
            EmptyWidget(symbol: "battery.0percent", text: "No accessories report a battery")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(batteries) { battery in
                    HStack {
                        Text(battery.name).lineLimit(1)
                        Spacer()
                        Gauge(value: Double(battery.percent), in: 0...100) { EmptyView() }
                            .gaugeStyle(.accessoryLinearCapacity)
                            .tint(battery.percent <= 20 ? Color.red : Color.green)
                            .frame(width: 80)
                        Text(verbatim: "\(battery.percent)%").font(.caption.monospacedDigit()).frame(width: 38, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// Catches scroll wheel and trackpad scrolling over the island; SwiftUI has no handler for it.
private struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (Double, Double) -> Void

    func makeNSView(context: Context) -> ScrollCatchingView {
        let view = ScrollCatchingView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: ScrollCatchingView, context: Context) {
        view.onScroll = onScroll
    }
}

final class ScrollCatchingView: NSView {
    var onScroll: ((Double, Double) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(Double(event.scrollingDeltaX), Double(event.scrollingDeltaY))
    }
}

/// The notch's parking spot for files: drop them on it, drag them off again.
private struct ShelfWidget: View {
    let shelf: FileShelf
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            if shelf.files.isEmpty {
                EmptyWidget(symbol: "tray", text: "Drop files here to park them.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.files, id: \.self) { url in
                            VStack(spacing: 4) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 32, height: 32)
                                Text(verbatim: shelfLabel(url.lastPathComponent))
                                    .font(.caption2).lineLimit(1)
                            }
                            .frame(width: 64)
                            .draggable(url)
                            .contextMenu {
                                Button { NSWorkspace.shared.open(url) } label: { Text("Open", bundle: .module) }
                                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                                    Text("Show in Finder", bundle: .module)
                                }
                                Button(role: .destructive) { shelf.remove(url) } label: {
                                    Text("Take off the shelf", bundle: .module)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                Button { shelf.clear() } label: { Text("Clear the shelf", bundle: .module) }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.sonaryAccent.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .task { shelf.prune() }
    }
}

/// Volume and brightness in the island, where the sound and display modules give a way in.
private struct ControlsWidget: View {
    let controls: NotchControls

    var body: some View {
        let volume = controls.volume?()
        let brightness = controls.brightness?()
        if volume == nil, brightness == nil {
            EmptyWidget(symbol: "slider.horizontal.3", text: "Turn on Sound or Display to control them here")
        } else {
            VStack(spacing: 14) {
                if let volume, let set = controls.setVolume {
                    slider(value: volume, low: "speaker.fill", high: "speaker.wave.3.fill",
                           label: Text("Volume", bundle: .module), set: set)
                }
                if let brightness, let set = controls.setBrightness {
                    slider(value: brightness, low: "sun.min", high: "sun.max.fill",
                           label: Text("Brightness", bundle: .module), set: set)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func slider(value: Double, low: String, high: String, label: Text,
                        set: @escaping @MainActor (Double) -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: low).foregroundStyle(.secondary).frame(width: 18)
            Slider(value: Binding(get: { value }, set: { set($0) }), in: 0...1)
                .tint(Color.sonaryAccent)
            Image(systemName: high).foregroundStyle(.secondary).frame(width: 22)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

/// The scratchpad's current note, to read and change without leaving the app in front.
private struct NotesWidget: View {
    let controls: NotchControls

    var body: some View {
        if let notes = controls.notes, let setNotes = controls.setNotes {
            TextEditor(text: Binding(get: { notes() }, set: { setNotes($0) }))
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            EmptyWidget(symbol: "note.text", text: "Turn on Tools to keep notes here")
        }
    }
}
