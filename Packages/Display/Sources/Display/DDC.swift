// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Taken from vorssaint-utils (Sources/Vorssaint/Services/Display/BrightnessSupport.swift and
// BrightnessService.swift, commit 26d3c9e199eb3afc8f43ce8bd83210b5754421bd) and modified for
// Sonary: only the DDC/CI brightness path (packets, reply parsing, display-to-service matching,
// the IORegistry walk, probing and paced writes), moved into one controller that runs on its own
// queue. Keyboard light, gamma dimming, display switching and key routing are left out.

import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics

/// Pure DDC/CI helpers: packet building, reply parsing, value scaling and the display-to-service
/// match score. No IOKit here, so the tests cover every byte.
enum DDCSupport {
    /// VCP code for luminance in the DDC/CI standard.
    static let luminanceCode: UInt8 = 0x10
    /// 7-bit I2C address DDC displays listen on.
    static let chipAddress: UInt32 = 0x37
    /// Sub-address DDC hosts write through.
    static let dataAddress: UInt32 = 0x51

    // Field-proven pacing: displays lose I2C transactions that arrive back to back, so every
    // write waits first, reads settle longer, and failures retry after a pause.
    static let writePauseMicroseconds: UInt32 = 10_000
    static let readPauseMicroseconds: UInt32 = 50_000
    static let retryPauseMicroseconds: UInt32 = 20_000
    static let writeCycles = 2
    static let retryAttempts = 4
    static let replyLength = 11
    /// A host waits at least 50 ms after one command before the next; monitors fed faster can
    /// drop their signal until they are power cycled.
    static let commandIntervalMicroseconds: UInt64 = 50_000

    static func probeAttempts() -> Int { retryAttempts + 1 }

    /// Some monitors answer nothing until a second request arrives right behind the first; the
    /// last probe attempt pairs them before a silent channel is written off as write-only.
    static func probeWriteCycles(isFinalAttempt: Bool) -> Int {
        isFinalAttempt ? writeCycles : 1
    }

    /// How long the next command must still wait, given when the previous one to the same
    /// display finished.
    static func commandDelay(nowMicroseconds: UInt64, lastCommandEndMicroseconds: UInt64?) -> UInt32 {
        guard let last = lastCommandEndMicroseconds, last <= nowMicroseconds else { return 0 }
        let elapsed = nowMicroseconds - last
        guard elapsed < commandIntervalMicroseconds else { return 0 }
        return UInt32(commandIntervalMicroseconds - elapsed)
    }

    /// Wraps a DDC payload: length-tagged header, payload, XOR checksum seeded with the
    /// destination and source addresses, as DDC/CI specifies.
    static func packet(payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [UInt8(0x80 | (payload.count + 1)), UInt8(payload.count)]
        bytes.append(contentsOf: payload)
        let seed = UInt8(chipAddress << 1) ^ UInt8(dataAddress)
        bytes.append(bytes.reduce(seed) { $0 ^ $1 })
        return bytes
    }

    /// Set VCP Feature packet.
    static func writePacket(code: UInt8, value: UInt16) -> [UInt8] {
        packet(payload: [code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Get VCP Feature request packet.
    static func readRequestPacket(code: UInt8) -> [UInt8] {
        packet(payload: [code])
    }

    /// Parses a Get VCP Feature reply: checksum first, then the big-endian maximum and current
    /// values. Anything malformed, or a reply for another control, reads as no reply.
    static func parseReply(_ reply: [UInt8], code: UInt8) -> (current: UInt16, maximum: UInt16)? {
        guard reply.count >= replyLength else { return nil }
        let checksum = reply[0..<(reply.count - 1)].reduce(UInt8(0x50)) { $0 ^ $1 }
        guard checksum == reply[reply.count - 1], reply[2] == 0x02, reply[4] == code else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return (current, maximum)
    }

    /// A display that reports no range still accepts writes; treat it as 0-100.
    static func sanitizedMaximum(_ maximum: UInt16) -> UInt16 {
        maximum > 0 ? maximum : 100
    }

    /// DDC value to the 0...1 slider scale.
    static func normalized(current: UInt16, maximum: UInt16) -> Double {
        let ceiling = sanitizedMaximum(maximum)
        return min(max(Double(current) / Double(ceiling), 0), 1)
    }

    /// Slider value to the display's own scale, rounded to the nearest step.
    static func deviceValue(for normalized: Double, maximum: UInt16) -> UInt16 {
        let ceiling = sanitizedMaximum(maximum)
        let clamped = min(max(normalized, 0), 1)
        return UInt16((clamped * Double(ceiling)).rounded())
    }

    /// What CoreDisplay says about a display, for matching it to its I2C service.
    struct DisplayIdentity {
        var vendorID: Int64?
        var productID: Int64?
        var weekOfManufacture: Int64?
        var yearOfManufacture: Int64?
        var horizontalImageSize: Int64?
        var verticalImageSize: Int64?
        var ioDisplayLocation: String?
        var productName: String?
        var serialNumber: Int64?
    }

    /// What the IORegistry walk collected for one external service.
    struct ServiceIdentity {
        var edidUUID = ""
        var ioDisplayLocation = ""
        var productName = ""
        var serialNumber: Int64 = 0
        var ordinal = 0
    }

    /// The EDID UUID embeds identity fields at fixed positions; each one that matches the
    /// display scores a point, and the IORegistry path match is decisive on its own.
    static func matchScore(service: ServiceIdentity, display: DisplayIdentity) -> Int {
        var score = 0
        func uuidChunk(at location: Int) -> String {
            String(service.edidUUID.prefix(location + 4).suffix(4))
        }
        if let vendor = display.vendorID, vendor > 0 {
            let key = String(format: "%04X", UInt16(clamping: vendor))
            if key != "0000", key == uuidChunk(at: 0) { score += 1 }
        }
        if let product = display.productID, product > 0 {
            let value = UInt16(clamping: product)
            let key = String(format: "%02X%02X", UInt8(value & 0xFF), UInt8(value >> 8))
            if key != "0000", key == uuidChunk(at: 4) { score += 1 }
        }
        if let week = display.weekOfManufacture, let year = display.yearOfManufacture, year >= 1990 {
            let key = String(format: "%02X%02X", UInt8(clamping: week), UInt8(clamping: year - 1990))
            if key != "0000", key == uuidChunk(at: 19) { score += 1 }
        }
        if let horizontal = display.horizontalImageSize, let vertical = display.verticalImageSize {
            let key = String(format: "%02X%02X", UInt8(clamping: horizontal / 10), UInt8(clamping: vertical / 10))
            if key != "0000", key == uuidChunk(at: 30) { score += 1 }
        }
        if !service.ioDisplayLocation.isEmpty, service.ioDisplayLocation == display.ioDisplayLocation {
            score += 10
        }
        if !service.productName.isEmpty, service.productName.lowercased() == display.productName?.lowercased() {
            score += 1
        }
        if service.serialNumber != 0, service.serialNumber == display.serialNumber {
            score += 1
        }
        return score
    }

    /// Greedy assignment, best scores first: each display and each service is used at most
    /// once, and zero-score pairs never match. Returns display index to service ordinal.
    static func assignServices(scores: [(displayIndex: Int, serviceOrdinal: Int, score: Int)]) -> [Int: Int] {
        var assignment: [Int: Int] = [:]
        var takenServices = Set<Int>()
        for entry in scores.sorted(by: { $0.score > $1.score }) where entry.score > 0 {
            guard assignment[entry.displayIndex] == nil, !takenServices.contains(entry.serviceOrdinal) else { continue }
            assignment[entry.displayIndex] = entry.serviceOrdinal
            takenServices.insert(entry.serviceOrdinal)
        }
        return assignment
    }
}

/// The private CoreDisplay symbols DDC needs, resolved once. Any that is missing leaves external
/// displays on the dimming overlay, never a crash.
enum DDCBridge {
    typealias CreateInfoDictionaryFn = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
    typealias CreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias I2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    // Opened once and only read afterwards, so sharing across threads is safe.
    private nonisolated(unsafe) static let coreDisplay = dlopen(
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)

    // Looked up on use, as the DisplayServices bridge does; dlsym on an open handle is cheap.
    static var createInfoDictionary: CreateInfoDictionaryFn? { symbol("CoreDisplay_DisplayCreateInfoDictionary") }
    static var createWithService: CreateWithServiceFn? { symbol("IOAVServiceCreateWithService") }
    static var writeI2C: I2CFn? { symbol("IOAVServiceWriteI2C") }
    static var readI2C: I2CFn? { symbol("IOAVServiceReadI2C") }

    static var isAvailable: Bool { createWithService != nil && writeI2C != nil && readI2C != nil }

    private static func symbol<T>(_ name: String) -> T? {
        guard let coreDisplay, let pointer = dlsym(coreDisplay, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

/// Brightness over DDC/CI for regular external monitors, which macOS's own brightness control
/// does not reach. Everything that touches the I2C bus runs on one serial queue, paced the way
/// monitors need, so a slider drag never blocks the interface or floods the display.
final class DDCController: @unchecked Sendable {
    /// What probing a display found.
    enum Probe: Sendable, Equatable {
        /// The monitor answered with its brightness, 0...1.
        case readable(Double)
        /// Writes are accepted but the monitor never answers a read.
        case writeOnly
    }

    private struct Route {
        let service: CFTypeRef
        let maximum: UInt16
    }

    private let queue = DispatchQueue(label: "sonary.display.ddc", qos: .userInitiated)
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var routes: [CGDirectDisplayID: Route] = [:]
    /// The newest level wanted per display, guarded by `lock`. A drag overwrites it, so only the
    /// latest value is sent once the bus is free.
    private var pending: [CGDirectDisplayID: Double] = [:]
    /// Only touched on `queue`.
    private var commandEnds: [CGDirectDisplayID: UInt64] = [:]

    func hasRoute(_ id: CGDirectDisplayID) -> Bool {
        lock.withLock { routes[id] != nil }
    }

    /// Drops every route, for when the screens changed and the services may be stale.
    func forgetRoutes() {
        lock.withLock {
            routes.removeAll()
            pending.removeAll()
        }
    }

    /// Forgets displays that are gone.
    func keepOnly(_ ids: Set<CGDirectDisplayID>) {
        lock.withLock {
            routes = routes.filter { ids.contains($0.key) }
            pending = pending.filter { ids.contains($0.key) }
        }
    }

    /// Matches the displays to their I2C services and asks each for its brightness. The result,
    /// on the queue, lists the displays DDC reaches; the rest stay on the overlay.
    func discover(_ ids: [CGDirectDisplayID],
                  completion: @escaping @Sendable ([CGDirectDisplayID: Probe]) -> Void) {
        guard !ids.isEmpty, DDCBridge.isAvailable else { return completion([:]) }
        queue.async { [self] in
            let services = Self.externalServices()
            let identities = ids.map { Self.identity(of: $0) }
            var scores: [(displayIndex: Int, serviceOrdinal: Int, score: Int)] = []
            for (index, identity) in identities.enumerated() {
                for service in services {
                    scores.append((index, service.identity.ordinal,
                                   DDCSupport.matchScore(service: service.identity, display: identity)))
                }
            }
            var assignment = DDCSupport.assignServices(scores: scores)
            // One display and one service left can only belong to each other (EDID data is
            // sometimes too sparse to score).
            if assignment.isEmpty, ids.count == 1, services.count == 1 {
                assignment = [0: services[0].identity.ordinal]
            }
            var found: [CGDirectDisplayID: Probe] = [:]
            for (index, id) in ids.enumerated() {
                guard let ordinal = assignment[index],
                      let matched = services.first(where: { $0.identity.ordinal == ordinal }) else { continue }
                switch probe(id, service: matched.service) {
                case let .replied(current, maximum):
                    let ceiling = DDCSupport.sanitizedMaximum(maximum)
                    lock.withLock { routes[id] = Route(service: matched.service, maximum: ceiling) }
                    found[id] = .readable(DDCSupport.normalized(current: current, maximum: ceiling))
                case .writeOnly:
                    lock.withLock { routes[id] = Route(service: matched.service, maximum: 100) }
                    found[id] = .writeOnly
                case .dead:
                    // The channel rejects every write (an HDMI conversion in the path, typically).
                    break
                }
            }
            completion(found)
        }
    }

    /// Sends a brightness to the display, coalescing a fast series into its last value.
    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        let first = lock.withLock {
            let wasEmpty = pending[id] == nil
            pending[id] = value
            return wasEmpty
        }
        guard first else { return }
        // A value that arrives while this one is on the bus finds `pending` empty again and
        // queues the next send, which then takes whatever is newest by its turn.
        queue.async { [self] in
            let next: (level: Double, route: Route)? = lock.withLock {
                guard let level = pending.removeValue(forKey: id), let route = routes[id] else { return nil }
                return (level, route)
            }
            guard let next else { return }
            let packet = DDCSupport.writePacket(code: DDCSupport.luminanceCode,
                                                value: DDCSupport.deviceValue(for: next.level, maximum: next.route.maximum))
            _ = send(to: id, service: next.route.service, packet: packet)
        }
    }

    // MARK: - Bus access (on `queue`)

    private enum RawProbe {
        case replied(current: UInt16, maximum: UInt16)
        case writeOnly
        case dead
    }

    private func pace(_ id: CGDirectDisplayID) {
        let now = DispatchTime.now().uptimeNanoseconds / 1_000
        let delay = DDCSupport.commandDelay(nowMicroseconds: now, lastCommandEndMicroseconds: commandEnds[id])
        if delay > 0 { usleep(delay) }
    }

    private func finished(_ id: CGDirectDisplayID) {
        commandEnds[id] = DispatchTime.now().uptimeNanoseconds / 1_000
    }

    private func send(to id: CGDirectDisplayID, service: CFTypeRef, packet: [UInt8]) -> Bool {
        guard let write = DDCBridge.writeI2C else { return false }
        pace(id)
        defer { finished(id) }
        var bytes = packet
        var success = false
        for attempt in 0...DDCSupport.retryAttempts {
            for _ in 0..<DDCSupport.writeCycles {
                usleep(DDCSupport.writePauseMicroseconds)
                let accepted = write(service, DDCSupport.chipAddress, DDCSupport.dataAddress,
                                     &bytes, UInt32(bytes.count)) == KERN_SUCCESS
                success = accepted || success
            }
            if success { return true }
            if attempt < DDCSupport.retryAttempts { usleep(DDCSupport.retryPauseMicroseconds) }
        }
        return success
    }

    /// Reads the luminance, and tells a monitor that only answers poorly apart from a path that
    /// cannot carry DDC at all (those reject every write).
    private func probe(_ id: CGDirectDisplayID, service: CFTypeRef) -> RawProbe {
        guard let write = DDCBridge.writeI2C, let read = DDCBridge.readI2C else { return .dead }
        pace(id)
        defer { finished(id) }
        var request = DDCSupport.readRequestPacket(code: DDCSupport.luminanceCode)
        var writeAccepted = false
        let attempts = DDCSupport.probeAttempts()
        for attempt in 0..<attempts {
            for _ in 0..<DDCSupport.probeWriteCycles(isFinalAttempt: attempt + 1 == attempts) {
                usleep(DDCSupport.writePauseMicroseconds)
                if write(service, DDCSupport.chipAddress, DDCSupport.dataAddress,
                         &request, UInt32(request.count)) == KERN_SUCCESS {
                    writeAccepted = true
                }
            }
            usleep(DDCSupport.readPauseMicroseconds)
            var reply = [UInt8](repeating: 0, count: DDCSupport.replyLength)
            if read(service, DDCSupport.chipAddress, 0, &reply, UInt32(reply.count)) == KERN_SUCCESS,
               let parsed = DDCSupport.parseReply(reply, code: DDCSupport.luminanceCode) {
                return .replied(current: parsed.current, maximum: parsed.maximum)
            }
            if attempt + 1 < attempts { usleep(DDCSupport.retryPauseMicroseconds) }
        }
        return writeAccepted ? .writeOnly : .dead
    }

    // MARK: - Display identity and the IORegistry walk

    private static func identity(of id: CGDirectDisplayID) -> DDCSupport.DisplayIdentity {
        var identity = DDCSupport.DisplayIdentity()
        guard let create = DDCBridge.createInfoDictionary,
              let info = create(id)?.takeRetainedValue() as NSDictionary? else { return identity }
        identity.vendorID = (info[kDisplayVendorID] as? NSNumber)?.int64Value
        identity.productID = (info[kDisplayProductID] as? NSNumber)?.int64Value
        identity.weekOfManufacture = (info[kDisplayWeekOfManufacture] as? NSNumber)?.int64Value
        identity.yearOfManufacture = (info[kDisplayYearOfManufacture] as? NSNumber)?.int64Value
        identity.horizontalImageSize = (info[kDisplayHorizontalImageSize] as? NSNumber)?.int64Value
        identity.verticalImageSize = (info[kDisplayVerticalImageSize] as? NSNumber)?.int64Value
        identity.ioDisplayLocation = info[kIODisplayLocationKey] as? String
        if let names = info["DisplayProductName"] as? [String: String] {
            identity.productName = names["en_US"] ?? names.first?.value
        }
        identity.serialNumber = (info[kDisplaySerialNumber] as? NSNumber)?.int64Value
        return identity
    }

    private struct ExternalService {
        var identity: DDCSupport.ServiceIdentity
        var service: CFTypeRef
    }

    /// External displays hang off the IORegistry as a framebuffer entry (identity: EDID UUID,
    /// product attributes) followed by its AV service proxy (the I2C endpoint). Only proxies
    /// marked External accept DDC; the built-in panel's is Embedded.
    private static func externalServices() -> [ExternalService] {
        guard let createWithService = DDCBridge.createWithService else { return [] }
        var results: [ExternalService] = []
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively),
                                            &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var pending = DDCSupport.ServiceIdentity()
        var ordinal = 0
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(entry) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &nameBuffer) == KERN_SUCCESS else { continue }
            let name = Self.string(nameBuffer)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                ordinal += 1
                pending = DDCSupport.ServiceIdentity()
                pending.ordinal = ordinal
                if let uuid = property(entry, "EDID UUID") as? String {
                    pending.edidUUID = uuid
                }
                var path = [CChar](repeating: 0, count: 512)
                if IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS {
                    pending.ioDisplayLocation = Self.string(path)
                }
                if let attributes = property(entry, "DisplayAttributes") as? NSDictionary,
                   let product = attributes["ProductAttributes"] as? NSDictionary {
                    pending.productName = product["ProductName"] as? String ?? ""
                    pending.serialNumber = (product["SerialNumber"] as? NSNumber)?.int64Value ?? 0
                }
            } else if name == "DCPAVServiceProxy" {
                guard let location = property(entry, "Location") as? String, location == "External",
                      let service = createWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
                else { continue }
                results.append(ExternalService(identity: pending, service: service))
            }
        }
        return results
    }

    /// A NUL-terminated C buffer as a string.
    private static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func property(_ entry: io_service_t, _ key: String) -> AnyObject? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively))?.takeRetainedValue()
    }
}
