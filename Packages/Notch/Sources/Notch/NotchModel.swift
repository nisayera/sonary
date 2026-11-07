import AppKit
import Observation
import UserNotifications

/// Ways into other parts of Sonary, given by the app. The island shows a control only when
/// its way in is there, so it works whichever modules are on.
public struct NotchControls {
    public var volume: (@MainActor () -> Double?)?
    public var setVolume: (@MainActor (Double) -> Void)?
    public var brightness: (@MainActor () -> Double?)?
    public var setBrightness: (@MainActor (Double) -> Void)?
    /// The scratchpad's current note.
    public var notes: (@MainActor () -> String)?
    public var setNotes: (@MainActor (String) -> Void)?

    public init(volume: (@MainActor () -> Double?)? = nil, setVolume: (@MainActor (Double) -> Void)? = nil,
                brightness: (@MainActor () -> Double?)? = nil, setBrightness: (@MainActor (Double) -> Void)? = nil,
                notes: (@MainActor () -> String)? = nil, setNotes: (@MainActor (String) -> Void)? = nil) {
        self.volume = volume
        self.setVolume = setVolume
        self.brightness = brightness
        self.setBrightness = setBrightness
        self.notes = notes
        self.setNotes = setNotes
    }
}

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
    @ObservationIgnored public var controls = NotchControls()
    /// Accessories already warned about, so a low battery warns once until it is charged.
    @ObservationIgnored private var warnedBatteries: Set<String> = []

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

    @ObservationIgnored private var hoverTask: Task<Void, Never>?

    /// Leaving closes at once; arriving opens after the chosen delay, or not at all when
    /// the island only opens on a click.
    func hoverChanged(_ inside: Bool) {
        hoverTask?.cancel()
        guard inside else { return update { $0.hoverChanged(false) } }
        guard settings.openOnHover else { return }
        let delay = settings.hoverDelay
        guard delay > 0 else { return update { $0.hoverChanged(true) } }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.update { $0.hoverChanged(true) }
        }
    }

    public func updateSettings(_ change: (inout NotchSettings) -> Void) {
        change(&settings)
        store.save(settings)
    }
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

    public func moveWidget(_ widget: NotchWidget, forward: Bool) {
        settings.move(widget, forward: forward)
        store.save(settings)
    }

    public func setLowBatteryWarning(_ on: Bool) {
        settings.lowBatteryWarning = on
        store.save(settings)
        if on { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }
    }

    /// A notice for each accessory that just fell to 20 %.
    private func warnAboutLowBatteries() {
        let result = lowBatteryAlerts(batteries, warned: warnedBatteries)
        warnedBatteries = result.warned
        guard settings.lowBatteryWarning else { return }
        for battery in result.alerts {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(battery.name) is low", bundle: .module)
            content.body = String(localized: "\(battery.percent) percent left. Time to charge it.", bundle: .module)
            content.sound = .default
            let request = UNNotificationRequest(identifier: "sonary.battery.\(battery.name)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
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
                    self?.warnAboutLowBatteries()
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
