import Foundation

/// The IPv4 address of the interface that carries the default route, as the user would
/// read it off their router: the first non-loopback address of en0 or similar.
public func preferredLocalAddress(_ addresses: [(interface: String, address: String)]) -> String? {
    let order = ["en0", "en1", "en2", "en3", "en4", "en5", "en6"]
    for name in order {
        if let match = addresses.first(where: { $0.interface == name }) { return match.address }
    }
    return addresses.first { !$0.interface.hasPrefix("lo") && !$0.interface.hasPrefix("utun") }?.address
}
