import Foundation

/// Settings that apply while the app with `bundleID` is frontmost.
public func effectiveSettings(_ base: MouseSettings, bundleID: String?) -> MouseSettings {
    guard let bundleID, let rule = base.appOverrides[bundleID] else { return base }
    var result = base
    if rule.disabled {
        result.linearScroll = false
        result.smoothScroll = false
        result.reverseScroll = false
        result.buttonMappings = []
        result.clickFilterMilliseconds = 0
        return result
    }
    if let value = rule.linearScroll { result.linearScroll = value }
    if let value = rule.smoothScroll { result.smoothScroll = value }
    if let value = rule.reverseScroll { result.reverseScroll = value }
    return result
}
