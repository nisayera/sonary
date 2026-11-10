// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sonary contributors
//
// Not part of Vorssaint: Sonary's one door into this code. Sonary runs Vorssaint's Dynamic
// Island as it is and nothing else of it, so every other Vorssaint feature is marked as not
// installed before the island starts, and no other service is ever asked to run.

import AppKit
import SwiftUI

public enum SonaryIsland {
    /// The island and the extensions of it that work on their own. Notifications, online lyrics
    /// and the agent readouts stay out: they read other apps or reach the network, which Sonary
    /// promises not to do unasked.
    private static let features: Set<AppFeature> = [
        .notch, .notchCalendar, .notchGestures, .notchTimer, .notchAccessories, .notchQueue,
        .notchLiveEqualizer, .notchDownloads, .notchWatch, .notchMascot,
    ]

    private static var prepared = false

    /// Registers Vorssaint's defaults once and limits what counts as installed to the island.
    private static func prepare() {
        guard !prepared else { return }
        prepared = true
        Defaults.register()
        NotchControlItem.keyboardLightIsSupported = { false }
        let defaults = UserDefaults.standard
        for feature in AppFeature.allCases {
            defaults.set(features.contains(feature), forKey: feature.availabilityKey)
        }
    }

    public static func start() {
        prepare()
        UserDefaults.standard.set(true, forKey: DefaultsKey.notchEnabled)
        NotchService.shared.syncWithPreferences()
    }

    public static func stop() {
        guard prepared else { return }
        UserDefaults.standard.set(false, forKey: DefaultsKey.notchEnabled)
        NotchService.shared.syncWithPreferences()
    }

    /// Vorssaint's own settings page for the island.
    public static func settingsView() -> AnyView {
        prepare()
        return AnyView(NotchSettings())
    }

    /// The accent Sonary uses, handed over so the island is tinted like the rest of the app.
    public static func setAccent(_ color: Color?) {
        SonaryIslandTint.accent = color
    }
}

enum SonaryIslandTint {
    static var accent: Color?
}
