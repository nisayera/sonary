import SwiftUI

/// One-line descriptions of the modules, shown in Settings and the menu panel.
enum ModuleInfo {
    static func summary(for id: String) -> LocalizedStringKey {
        switch id {
        case "monitor": "CPU, GPU, memory, network, disk, battery and temperatures, with history and alerts."
        case "mouse": "Linear or smooth scrolling, pointer acceleration, extra buttons, click filter and app exceptions."
        default: ""
        }
    }
}
