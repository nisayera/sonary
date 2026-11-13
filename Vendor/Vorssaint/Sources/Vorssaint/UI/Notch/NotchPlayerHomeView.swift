// SPDX-License-Identifier: GPL-3.0-or-later
//
// Added for Sonary: the open island's home in the layout of boring.notch
// (https://theboring.name): the player on the left with its cover and a glow
// of it, the week and the day's events on the right, and Home and Shelf tabs
// with the charge and Settings in the top row. Written for Sonary on top of
// Vorssaint's island components; no code of boring.notch is used.

import AppKit
import SwiftUI

/// The words this page adds, in the two languages Sonary speaks.
enum NotchPlayerHomeStrings {
    static func noEvents(_ language: AppLanguage) -> String {
        language == .de ? "Keine Termine" : "No events"
    }

    static func freeTime(_ language: AppLanguage) -> String {
        language == .de ? "Genieß die freie Zeit" : "Enjoy your free time"
    }

    static func home(_ language: AppLanguage) -> String { language == .de ? "Start" : "Home" }

    static func more(_ count: Int, _ language: AppLanguage) -> String {
        language == .de ? "+\(count) weitere" : "+\(count) more"
    }

    static func settingTitle(_ language: AppLanguage) -> String {
        language == .de ? "Startseite mit Player und Kalender" : "Home with player and calendar"
    }

    static func settingCaption(_ language: AppLanguage) -> String {
        language == .de
            ? "Die offene Insel zeigt links den Player mit Cover und rechts die Woche mit den Terminen, mit Tabs für Start und Ablage. Aus zeigt die bisherige Startseite mit Reglern und Kurzbefehlen."
            : "The open island shows the player with its cover on the left and the week with its events on the right, with tabs for Home and Shelf. Off shows the earlier home with levels and shortcuts."
    }
}

/// How the home divides its width: the calendar takes a fixed share once
/// there is room for both, and steps aside on a narrow island.
enum NotchPlayerHomeLayout {
    /// Whether the island is Sonary's: wide and flat, opening on the player and the calendar.
    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchPlayerHome) as? Bool ?? true
    }

    /// The open island's width, as wide as boring.notch's, and the height of its page below the top row.
    static let islandWidth: CGFloat = 640
    static let pageHeight: CGFloat = 118

    static let spacing: CGFloat = 18
    static let minimumPlayerWidth: CGFloat = 250

    /// The calendar's width, or nil when the player needs the whole island.
    static func calendarWidth(in width: CGFloat) -> CGFloat? {
        let calendar = min(250, max(196, (width * 0.4).rounded()))
        return width - calendar - spacing >= minimumPlayerWidth ? calendar : nil
    }

    /// The cover is as tall as the page allows, within what reads well.
    static func artwork(height: CGFloat) -> CGFloat { min(116, max(56, height - 14)) }
}

struct NotchPlayerHomeView: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var preview
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedDay: Date?

    private var mediaText: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var tint: Color { music.artworkTint?.color ?? .white }
    private var isIdle: Bool { !preview && music.playback == nil && !music.awaitingPlayback }

    private var showsCalendar: Bool {
        service.modules.contains(.calendar) && permissions.calendarAccess == .fullAccess
            && NotchPlayerHomeLayout.calendarWidth(in: size.width) != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: NotchPlayerHomeLayout.spacing) {
            player
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            if showsCalendar, let width = NotchPlayerHomeLayout.calendarWidth(in: size.width) {
                TimelineView(.everyMinute) { context in
                    calendarPane(now: context.date)
                }
                .frame(width: width)
                .frame(maxHeight: .infinity, alignment: .top)
                .environment(\.locale, l10n.language.formattingLocale())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .notchBand(trailing: { NotchPlayerHomeStatus(service: service) })
        // The calendar service already reads the days around today. The month
        // it shows belongs to the calendar page, so this page leaves it alone.
        .onAppear { if !preview { music.refreshAutomation() } }
    }

    // MARK: Player

    private var player: some View {
        let side = NotchPlayerHomeLayout.artwork(height: size.height)
        return HStack(alignment: .center, spacing: 16) {
            cover(side: side)
            ViewThatFits(in: .vertical) {
                details(timeline: true, artist: true)
                details(timeline: false, artist: true)
                details(timeline: false, artist: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The cover over a soft glow of itself, with the playing app's icon on
    /// its corner. With nothing playing it opens the music app instead.
    private func cover(side: CGFloat) -> some View {
        Button {
            if isIdle { _ = NotchPreferredPlayer.open(); return }
            if let track = music.playback?.track { RadialNowPlayingApplication.runningApplication(for: track)?.activate() }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let artwork = music.artwork, !reduceTransparency {
                    Image(nsImage: artwork).resizable().scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.19, style: .continuous))
                        .scaleEffect(1.12)
                        .blur(radius: 24)
                        .opacity(music.playback?.isPlaying == true ? 0.6 : 0.3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                NotchArtwork(image: music.artwork, size: side, source: music.playback?.track)
                    .scaleEffect(music.playback?.isPlaying == false ? 0.94 : 1)
                    .animation(.smooth(duration: 0.3), value: music.playback?.isPlaying)
                if music.artwork != nil, let track = music.playback?.track,
                   let icon = RadialNowPlayingApplication.icon(for: track) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: side * 0.26, height: side * 0.26)
                        .offset(x: side * 0.07, y: side * 0.07)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: side, height: side)
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: side * 0.19))
        .accessibilityLabel(mediaText.mediaNowPlaying)
        .help(mediaText.mediaNowPlaying)
    }

    private func details(timeline: Bool, artist: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { service.select(.music) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(music.playback?.track.title
                         ?? (music.awaitingPlayback ? mediaText.mediaNowPlaying : mediaText.mediaNothingPlaying))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if artist {
                        Text(music.commandFailed ? FeatureStrings.notchMusicExtras(l10n.language).playbackFailed
                             : music.playback?.track.artist ?? music.playback?.track.album
                                ?? (music.awaitingPlayback ? "" : FeatureStrings.notch(l10n.language).musicHint))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(music.commandFailed ? AnyShapeStyle(Color.orange)
                                             : AnyShapeStyle(tint.opacity(0.75)))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if timeline, let playback = music.playback, playback.duration > 0 {
                NotchMusicTimeline(playback: playback, service: music, tint: tint)
            }
            transport
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder private var transport: some View {
        if let playback = music.playback {
            NotchMusicTransport(playback: playback, compact: true)
        } else if isIdle, let player = NotchPreferredPlayer.current() {
            NotchMusicIdleTransport(compact: true, openTitle: NotchPreferredPlayer.openTitle(for: player))
        }
    }

    // MARK: Calendar

    private func calendarPane(now: Date) -> some View {
        let day = selectedDay ?? now
        let events = NotchCalendarSupport.events(calendar.events, on: day)
        return ViewThatFits(in: .vertical) {
            calendarColumn(day: day, now: now, events: events, rows: 3)
            calendarColumn(day: day, now: now, events: events, rows: 2)
            calendarColumn(day: day, now: now, events: events, rows: 1)
            calendarColumn(day: day, now: now, events: events, rows: 0)
        }
    }

    private func calendarColumn(day: Date, now: Date, events: [NotchCalendarEvent], rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { service.select(.calendar) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(day, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Text(day, format: .dateTime.year())
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NotchModule.calendar.title(l10n.language))
            NotchCalendarWeekStrip(focus: day, selectedDay: selectedDay, now: now, events: calendar.events,
                                   text: FeatureStrings.notchCalendar(l10n.language),
                                   select: { selectedDay = Calendar.current.isDate($0, inSameDayAs: now) ? nil : $0 },
                                   week: { selectedDay = nil })
            if rows > 0 {
                if events.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(NotchPlayerHomeStrings.noEvents(l10n.language))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        if rows > 1 {
                            Text(NotchPlayerHomeStrings.freeTime(l10n.language))
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                        }
                    }
                } else {
                    let shown = events.count > rows ? max(1, rows - 1) : rows
                    ForEach(events.prefix(shown)) { event in eventRow(event) }
                    if events.count > shown, rows > 1 {
                        Text(NotchPlayerHomeStrings.more(events.count - shown, l10n.language))
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
        }
    }

    private func eventRow(_ event: NotchCalendarEvent) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color.color)
                .frame(width: 3, height: 14)
            Text(event.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 4)
            if !event.allDay {
                Text(event.start, format: .dateTime.hour().minute())
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The end of the home's top row: the charge and the way to Settings.
struct NotchPlayerHomeStatus: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 6) {
            if let percent = service.power.chargePercent {
                HStack(spacing: 4) {
                    Text("\(percent)%").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    Image(systemName: NotchRestingBattery.symbol(for: service.power)).font(.system(size: 14))
                }
                .foregroundStyle(service.power.isCharging ? Color.green : .white.opacity(0.8))
                .accessibilityElement(children: .combine)
            }
            NotchIconButton(symbol: "gearshape.fill", title: l10n.s.menuSettings, action: service.openSettings)
        }
    }
}

/// Home and Shelf as tabs at the start of the top row, with the way to every
/// other section after them.
struct NotchPlayerHomeTabs: View {
    @ObservedObject var service: NotchService
    let showsSections: Bool
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 2) {
            NotchIconButton(symbol: "house.fill", title: NotchPlayerHomeStrings.home(l10n.language),
                            selected: service.selected == .controls) { service.select(.controls) }
            if service.modules.contains(.files) {
                NotchIconButton(symbol: "tray.fill", title: NotchModule.files.title(l10n.language),
                                selected: service.selected == .files) { service.select(.files) }
            }
            if showsSections { NotchSectionsButton(action: service.toggleSections) }
        }
    }
}
