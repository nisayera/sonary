// SPDX-License-Identifier: GPL-3.0-or-later
//
// Added for Sonary: the open island's home in the layout of boring.notch
// (https://theboring.name): the player on the left with its cover and a glow
// of it, the week and the day's events on the right, and Home and Shelf tabs
// with the charge and Settings in the top row. The measures follow
// boring.notch's own (GPL-3.0, TheBoredTeam): a 13 pt cover corner, the glow
// turned and blurred behind it, a 215 pt calendar with a wheel of days and
// the capsule behind the chosen tab. Written for Sonary on top of Vorssaint's
// island components.

import AppKit
import SwiftUI

/// The words this page adds, in the two languages Sonary speaks.
enum NotchPlayerHomeStrings {
    static func noEvents(_ language: AppLanguage) -> String {
        language == .de ? "Keine Termine" : "No events"
    }

    static func noEventsToday(_ language: AppLanguage) -> String {
        language == .de ? "Heute keine Termine" : "No events today"
    }

    static func freeTime(_ language: AppLanguage) -> String {
        language == .de ? "Genieß die freie Zeit!" : "Enjoy your free time!"
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

/// How the home divides its width: the calendar takes boring.notch's fixed
/// width once there is room for both, and steps aside on a narrow island.
enum NotchPlayerHomeLayout {
    static let spacing: CGFloat = 15
    static let minimumPlayerWidth: CGFloat = 250
    static let coverRadius: CGFloat = 13

    /// The calendar's width, or nil when the player needs the whole island.
    static func calendarWidth(in width: CGFloat) -> CGFloat? {
        let calendar: CGFloat = 215
        return width - calendar - spacing >= minimumPlayerWidth ? calendar : nil
    }

    /// The cover is as tall as the page allows, within what reads well.
    static func artwork(height: CGFloat) -> CGFloat { min(110, max(56, height - 10)) }

    /// The days the wheel offers: the ones the calendar has read.
    static func wheelDays(from now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDay: Date?

    private var mediaText: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var tint: Color { music.artworkTint?.color ?? .white }
    private var isIdle: Bool { !preview && music.playback == nil && !music.awaitingPlayback }
    private var isPlaying: Bool { music.playback?.isPlaying == true }
    private var accent: Color { Color(nsColor: .controlAccentColor) }
    private var grey: Color { Color(white: 0.65) }

    private var showsCalendar: Bool {
        service.modules.contains(.calendar) && permissions.calendarAccess == .fullAccess
            && NotchPlayerHomeLayout.calendarWidth(in: size.width) != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: NotchPlayerHomeLayout.spacing) {
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
        .onAppear { if !preview { music.refreshAutomation() } }
    }

    // MARK: Player

    private var player: some View {
        let side = NotchPlayerHomeLayout.artwork(height: size.height)
        return HStack(alignment: .center, spacing: 12) {
            cover(side: side).padding(5)
            ViewThatFits(in: .vertical) {
                details(timeline: true, artist: true)
                details(timeline: false, artist: true)
                details(timeline: false, artist: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The cover over a turned, blurred glow of itself, with the playing
    /// app's icon on its corner. Paused, it steps back and dims. With nothing
    /// playing it opens the music app instead.
    private func cover(side: CGFloat) -> some View {
        Button {
            if isIdle, NotchPreferredPlayer.open() { return }
            service.select(.music)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let artwork = music.artwork, !reduceTransparency {
                    Image(nsImage: artwork).resizable().scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: NotchPlayerHomeLayout.coverRadius))
                        .scaleEffect(x: 1.3, y: 1.4)
                        .rotationEffect(.degrees(92))
                        .blur(radius: 40)
                        .opacity(isPlaying ? 0.5 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                ZStack(alignment: .bottomTrailing) {
                    NotchArtwork(image: music.artwork, size: side, source: music.playback?.track)
                        .clipShape(RoundedRectangle(cornerRadius: NotchPlayerHomeLayout.coverRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: NotchPlayerHomeLayout.coverRadius)
                                .fill(.black.opacity(music.playback != nil && !isPlaying ? 0.45 : 0))
                        }
                    if music.artwork != nil, let track = music.playback?.track,
                       let icon = RadialNowPlayingApplication.icon(for: track) {
                        Image(nsImage: icon).resizable().interpolation(.high)
                            .frame(width: 30, height: 30)
                            .offset(x: 10, y: 10)
                            .accessibilityHidden(true)
                    }
                }
                .scaleEffect(music.playback != nil && !isPlaying ? 0.85 : 1)
            }
            .frame(width: side, height: side)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isPlaying)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mediaText.mediaNowPlaying)
        .help(mediaText.mediaNowPlaying)
    }

    private func details(timeline: Bool, artist: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { service.select(.music) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(music.playback?.track.title
                         ?? (music.awaitingPlayback ? mediaText.mediaNowPlaying : mediaText.mediaNothingPlaying))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if artist {
                        Text(music.commandFailed ? FeatureStrings.notchMusicExtras(l10n.language).playbackFailed
                             : music.playback?.track.artist ?? music.playback?.track.album
                                ?? (music.awaitingPlayback ? "" : FeatureStrings.notch(l10n.language).musicHint))
                            .font(.headline.weight(.medium))
                            .foregroundStyle(music.commandFailed ? AnyShapeStyle(Color.orange)
                                             : music.artworkTint == nil ? AnyShapeStyle(Color.gray)
                                             : AnyShapeStyle(tint.opacity(0.85)))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if timeline, let playback = music.playback, playback.duration > 0 {
                NotchMusicTimeline(playback: playback, service: music, tint: tint)
                    .padding(.top, 5)
            }
            transport
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.leading, 5)
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
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button { service.select(.calendar) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(day, format: .dateTime.month(.abbreviated))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(day, format: .dateTime.year())
                            .font(.title3.weight(.light))
                            .foregroundStyle(grey)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NotchModule.calendar.title(l10n.language))
                dayWheel(day: day, now: now)
            }
            if events.isEmpty {
                ViewThatFits(in: .vertical) {
                    emptyDay(day: day, now: now, icon: true)
                    emptyDay(day: day, now: now, icon: false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { Divider().overlay(Color.gray.opacity(0.2)) }
                            eventRow(event)
                        }
                    }
                }
                .scrollIndicators(.never)
                .padding(.top, 4)
            }
        }
    }

    /// The days in a row that scrolls sideways, fading into the island at
    /// both ends: the weekday over the date, today's date on the accent and
    /// the chosen day on a soft plate.
    private func dayWheel(day: Date, now: Date) -> some View {
        let days = NotchPlayerHomeLayout.wheelDays(from: now)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { date in
                        let chosen = Calendar.current.isDate(date, inSameDayAs: day)
                        let today = Calendar.current.isDate(date, inSameDayAs: now)
                        Button {
                            selectedDay = today ? nil : date
                            withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(date, anchor: .center) }
                        } label: {
                            VStack(spacing: 8) {
                                Text(date, format: .dateTime.weekday(.abbreviated))
                                    .font(.caption)
                                    .foregroundStyle(chosen ? Color.white : grey)
                                Text(date, format: .dateTime.day())
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(chosen ? Color.white : Color(white: today ? 0.9 : 0.65))
                                    .frame(width: 20, height: 20)
                                    .background(today ? accent : .clear, in: Circle())
                            }
                            .padding(4)
                            .frame(minWidth: 32)
                            .background(chosen ? accent.opacity(0.25) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(date)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.never)
            .frame(height: 50)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                       .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
    }

    private func emptyDay(day: Date, now: Date, icon: Bool) -> some View {
        VStack(spacing: 1) {
            if icon {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(grey)
                    .padding(.bottom, 2)
            }
            Text(Calendar.current.isDate(day, inSameDayAs: now)
                 ? NotchPlayerHomeStrings.noEventsToday(l10n.language) : NotchPlayerHomeStrings.noEvents(l10n.language))
                .font(.subheadline)
                .foregroundStyle(.white)
            Text(NotchPlayerHomeStrings.freeTime(l10n.language))
                .font(.caption)
                .foregroundStyle(grey)
        }
        .accessibilityElement(children: .combine)
    }

    private func eventRow(_ event: NotchCalendarEvent) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color.color)
                .frame(width: 3, height: 16)
            Text(event.title)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !event.allDay {
                Text(event.start, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(grey)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The end of the home's top row, as boring.notch ends its own: the way to
/// Settings on a black disc, then the charge beside its battery.
struct NotchPlayerHomeStatus: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 4) {
            Button(action: service.openSettings) {
                Image(systemName: "gear")
                    .imageScale(.medium)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuSettings)
            .accessibilityLabel(l10n.s.menuSettings)
            if let percent = service.power.chargePercent {
                HStack(spacing: 4) {
                    Text("\(percent)%").font(.callout).monospacedDigit().foregroundStyle(.white)
                    NotchPlayerHomeBattery(level: percent, charging: service.power.isCharging)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.system(.headline, design: .rounded))
    }
}

/// The battery as boring.notch draws it: the outline with the charge filling
/// it from the left, green while charging and red when nearly empty.
struct NotchPlayerHomeBattery: View {
    let level: Int
    let charging: Bool

    static func fill(level: Int, width: CGFloat) -> CGFloat {
        max(0, min(1, CGFloat(level) / 100)) * width
    }

    var body: some View {
        let colour: Color = charging ? .green : level <= 20 ? .red : .white
        ZStack(alignment: .leading) {
            Image(systemName: "battery.0")
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 27)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(colour)
                .frame(width: Self.fill(level: level, width: 19), height: 8)
                .padding(.leading, 2.5)
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24)
            }
        }
        .frame(width: 27, height: 13)
        .accessibilityHidden(true)
    }
}

/// Home and Shelf as boring.notch's tabs at the start of the top row: one
/// capsule that slides behind the chosen one, with the way to every other
/// section after them.
struct NotchPlayerHomeTabs: View {
    @ObservedObject var service: NotchService
    let showsSections: Bool
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var plate

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                tab("house.fill", title: NotchPlayerHomeStrings.home(l10n.language), module: .controls)
                if service.modules.contains(.files) {
                    tab("tray.fill", title: NotchModule.files.title(l10n.language), module: .files)
                }
            }
            .clipShape(Capsule())
            if showsSections { NotchSectionsButton(action: service.toggleSections) }
        }
    }

    private func tab(_ symbol: String, title: String, module: NotchModule) -> some View {
        let chosen = service.selected == module
        return Button {
            withAnimation(reduceMotion ? nil : .smooth) { service.select(module) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(chosen ? Color.white : Color.gray)
                .padding(.horizontal, 15)
                .frame(height: 26)
                .background {
                    if chosen {
                        Capsule().fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "plate", in: plate)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
