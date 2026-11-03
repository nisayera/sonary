import Foundation

private let trackingKeys: Set<String> = [
    "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "mc_eid", "mc_cid", "igshid", "igsh", "yclid",
    "_hsenc", "_hsmi", "mkt_tok", "vero_id", "oly_enc_id", "oly_anon_id", "rb_clickid", "s_cid", "ref_src", "si",
]

/// Removes tracking parameters (utm_*, fbclid, gclid, ...) from an http(s) link. Returns nil when nothing changes
/// or the text is not a single link.
public func cleanedURL(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains(where: \.isWhitespace),
          var components = URLComponents(string: trimmed),
          let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
          components.host != nil,
          let items = components.queryItems, !items.isEmpty else { return nil }
    let kept = items.filter { item in
        let name = item.name.lowercased()
        return !name.hasPrefix("utm_") && !trackingKeys.contains(name)
    }
    guard kept.count != items.count else { return nil }
    components.queryItems = kept.isEmpty ? nil : kept
    return components.string
}
