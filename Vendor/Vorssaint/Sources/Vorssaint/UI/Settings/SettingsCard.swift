// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One rounded group of related controls on a redesigned Settings page, with
/// an optional heading. The same card the Dynamic Island page draws, so the
/// pages read as one design.
struct SettingsCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    // Sonary: drawn the way Sonary's own settings cards are (SonaryUI.SettingsCard), so the pages
    // taken over from Vorssaint read as part of the same window: the heading above the card, the
    // card one list of rows with hairlines between them.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) { rows }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private var rows: some View {
        if #available(macOS 15.0, *) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                    if index > 0 {
                        Divider().padding(.horizontal, 14).accessibilityHidden(true)
                    }
                    subview
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 13) { content }.padding(16)
        }
    }
}

/// Where a row's text column starts, so follow-up controls can line up with it.
let settingsRowTextInset: CGFloat = 26 + 12

/// Icon, title, one line of explanation and the control on the right. A nil
/// symbol shows the app's own menu bar glyph, for rows about that icon.
struct SettingsRow<Accessory: View>: View {
    let symbol: String?
    let title: String
    let badge: String?
    let caption: String?
    let accessory: Accessory

    init(symbol: String?, title: String, badge: String? = nil, caption: String? = nil,
         @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.badge = badge
        self.caption = caption
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            iconTile
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                            .accessibilityHidden(true)
                    }
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
    }

    // Sonary: the icon badge of Sonary's rows (SonaryUI.IconBadge): white symbol on the accent.
    // A nil symbol shows Sonary's menu bar icon.
    @ViewBuilder
    private var iconTile: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13.5, weight: .semibold))
            } else {
                MenuBarGlyph().frame(width: 15, height: 15)
            }
        }
        .foregroundStyle(Color.white)
        .frame(width: 26, height: 26)
        .background(shape.fill(Color.accentColor.gradient))
        .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// A switch for an option that needs another feature. While it cannot be
/// used, its feature uninstalled or something else ruling it out, the option
/// reads greyed and off, since a disabled switch looks like one that is just
/// off, and a readable line under it says why.
struct SettingsFeatureSwitchRow: View {
    let symbol: String
    let title: String
    var caption: String? = nil
    @Binding var isOn: Bool
    let feature: AppFeature
    /// False while something else rules the option out, as the caption says.
    var enabled = true
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared

    var body: some View {
        let installed = features.isAvailable(feature)
        let usable = installed && enabled
        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(symbol: symbol, title: title, caption: usable ? caption : nil) {
                Toggle(title, isOn: usable ? $isOn : .constant(false)).labelsHidden().toggleStyle(.switch)
            }
            .disabled(!usable)
            .saturation(usable ? 1 : 0)
            .opacity(usable ? 1 : 0.45)
            if !installed {
                HStack(spacing: 10) {
                    Text(feature.enableReason(l10n))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(FeatureStrings.notchEditor(l10n.language).openFeatures) { feature.showInFeatures() }
                        .controlSize(.small)
                }
                .padding(.leading, settingsRowTextInset)
            } else if !usable, let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }
}

/// A row that picks one of a few options: segments beside the title while the
/// row fits on one line, under the title otherwise, and a menu there when the
/// segments don't fit either. A row wider than its column would center the page
/// and cut it on both sides.
struct SettingsChoiceRow<Value: Hashable, Options: View>: View {
    let symbol: String?
    let title: String
    @Binding var selection: Value
    let options: Options

    init(symbol: String?, title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.symbol = symbol
        self.title = title
        _selection = selection
        self.options = options()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            SettingsRow(symbol: symbol, title: title) {
                picker.pickerStyle(.segmented).fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(symbol: symbol, title: title) { EmptyView() }
                ViewThatFits(in: .horizontal) {
                    picker.pickerStyle(.segmented).fixedSize()
                    picker.pickerStyle(.menu).fixedSize()
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) { options }.labelsHidden()
    }
}

/// A row whose choice is a menu: beside the title while the row fits on one
/// line, under the title otherwise, lined up with its text, or with its icon
/// when the menu is wider than the text leaves room for. A menu kept beside a
/// title that has to wrap squeezes the title letter by letter, and a row
/// wider than its column would center the page and cut it on both sides.
struct SettingsMenuRow<Value: Hashable, Options: View>: View {
    let symbol: String?
    let title: String
    @Binding var selection: Value
    let options: Options

    init(symbol: String?, title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.symbol = symbol
        self.title = title
        _selection = selection
        self.options = options()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            SettingsRow(symbol: symbol, title: title) { menu }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(symbol: symbol, title: title) { EmptyView() }
                // Only the menu's width decides here: a title too long for one
                // line wraps above it either way.
                ViewThatFits(in: .horizontal) {
                    menu.padding(.leading, settingsRowTextInset)
                    menu
                }
            }
        }
    }

    private var menu: some View {
        Picker(title, selection: $selection) { options }.pickerStyle(.menu).labelsHidden().fixedSize()
    }
}

/// A switch pushed to the trailing edge with its label at the leading one,
/// so a shared control that carries its own label lines up with the rows
/// around it on a redesigned page.
struct TrailingSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
