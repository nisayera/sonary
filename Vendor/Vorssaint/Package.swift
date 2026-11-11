// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Vorssaint's sources as a library for Sonary. The targets are Vorssaint's own (see its
// Package.swift); the executable became a library and `main.swift` was left out, because Sonary
// starts only the Dynamic Island, through `Sources/Vorssaint/SonaryBridge.swift`.

import PackageDescription

let package = Package(
    name: "Vorssaint",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VorssaintKit", targets: ["Vorssaint"])
    ],
    targets: [
        .systemLibrary(name: "CoreAudioTapCompat", path: "Sources/CoreAudioTapCompat"),
        .systemLibrary(name: "HIDEventSystem", path: "Sources/HIDEventSystem"),
        .systemLibrary(name: "VMStatisticsCompat", path: "Sources/VMStatisticsCompat"),
        .target(
            name: "RecorderGIFCodec",
            path: "Sources/RecorderGIFCodec",
            sources: ["RecorderGIFCodec.c", "vendor/cgif/cgif_raw.c"]
        ),
        .target(
            name: "Vorssaint",
            dependencies: ["VMStatisticsCompat", "HIDEventSystem", "CoreAudioTapCompat", "RecorderGIFCodec"],
            path: "Sources/Vorssaint",
            // Not optimized, in releases too: built by Xcode, the optimizer did not get through
            // this target in an hour, neither as a whole module nor file by file. The flag comes
            // after Xcode's own -O and wins. To be lifted once the slow file is found.
            swiftSettings: [.unsafeFlags(["-Onone"])]
        )
    ]
)
