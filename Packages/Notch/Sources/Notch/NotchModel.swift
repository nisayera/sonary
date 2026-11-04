import AppKit
import Observation

/// Everything the island shows, plus its open/closed state.
@MainActor
@Observable
public final class NotchModel {
    public static let expandedSize = CGSize(width: 440, height: 220)

    public private(set) var state = NotchState()
    public var selectedWidget: NotchWidget = .music
    public private(set) var notchSize = CGSize(width: NotchGeometry.simulatedWidth, height: 32)
    public private(set) var settings: NotchSettings
    public private(set) var timer = CountdownTimer()
    public private(set) var batteries: [AccessoryBattery] = []

    public let music = NowPlayingCenter()
    public let calendar = CalendarSource()
    public let downloads = DownloadsWatcher()
    public let shelf = FileShelf()
    public let camera = NotchCamera()

    /// Called when the island opens or closes, so the window can change size.
    @ObservationIgnored var presentationChanged: ((NotchPresentation) -> Void)?
    @ObservationIgnored private let store: NotchSettingsStore
    @ObservationIgnored private var batteryTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored var gestures = NotchGestureState()

    public init(defaults: UserDefaults) {
        store = NotchSettingsStore(defaults: defaults)
        settings = store.load()
        selectedWidget = settings.widgets.first ?? .music
    }

    public var presentation: NotchPresentation { state.presentation }

    func start() {
        applyWidgets()
    }

    func stop() {
        music.stop()
        downloads.stop()
        batteryTask?.cancel()
        batteryTask = nil
        timerTask?.cancel()
        timerTask = nil
    }

    func setNotchSize(_ size: CGSize) { notchSize = size }

    func hoverChanged(_ inside: Bool) { update { $0.hoverChanged(inside) } }
    func clicked() { update { $0.clicked() } }
    func clickedOutside() { update { $0.clickedOutside() } }

    private func update(_ change: (inout NotchState) -> Void) {
        let before = state.presentation
        change(&state)
        if state.presentation != before { presentationChanged?(state.presentation) }
    }

    public func setWidget(_ widget: NotchWidget, on: Bool) {
        settings.set(widget, on: on)
        store.save(settings)
        if !settings.isOn(selectedWidget) { selectedWidget = settings.widgets.first ?? .music }
        applyWidgets()
        if widget == .calendar, on, !calendar.hasAccess {
            Task { await calendar.requestAccess() }
        }
    }

    public func setShowOnScreensWithoutNotch(_ show: Bool) {
        settings.showOnScreensWithoutNotch = show
        store.save(settings)
    }

    private func applyWidgets() {
        if settings.isOn(.music) { music.start() } else { music.stop() }
        if settings.isOn(.downloads) { downloads.start() } else { downloads.stop() }
        if settings.isOn(.calendar) { calendar.refresh() }
        if settings.isOn(.batteries) {
            guard batteryTask == nil else { return }
            batteryTask = Task { [weak self] in
                while !Task.isCancelled {
                    let read = AccessoryBatteryReader.read()
                    self?.batteries = read
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        } else {
            batteryTask?.cancel()
            batteryTask = nil
            batteries = []
        }
    }

    // MARK: Timer

    public func startTimer(minutes: Int) {
        timer.start(duration: TimeInterval(minutes * 60), at: Date())
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.timer.isFinished(at: Date()) {
                    self.timer.cancel()
                    NSSound(named: "Glass")?.play()
                    return
                }
            }
        }
    }

    public func cancelTimer() {
        timer.cancel()
        timerTask?.cancel()
        timerTask = nil
    }
}

extension NotchModel {
    /// Handles a scroll on the island: open, close or switch widget.
    func scrolled(deltaX: Double, deltaY: Double) {
        guard let action = gestures.scrolled(deltaX: deltaX, deltaY: deltaY, presentation: presentation) else { return }
        switch action {
        case .open:
            clicked()
        case .close:
            if state.isPinned { clicked() }
            hoverChanged(false)
        case .nextWidget, .previousWidget:
            guard let next = neighbourWidget(selectedWidget, in: settings.widgets, forward: action == .nextWidget) else { return }
            selectedWidget = next
        }
    }
}
