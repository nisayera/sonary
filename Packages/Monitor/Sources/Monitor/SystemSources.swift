import Darwin
import Foundation
import IOKit.ps

/// Real readings from the running Mac. GPU and temperatures are provided by `SensorReading` (see SensorReader).
public struct SystemSources: MetricsSources {
    private let sensors: any SensorReading

    public init(sensors: any SensorReading = NoSensors()) {
        self.sensors = sensors
    }

    public func cpuTicks() -> CPUTicks {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else {
            return CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(task_self_trap(), vm_address_t(bitPattern: info), size)
        }
        var ticks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let stride = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(cpuCount) {
            let base = stride * cpu
            ticks.user += tickCount(info[base + Int(CPU_STATE_USER)])
            ticks.system += tickCount(info[base + Int(CPU_STATE_SYSTEM)])
            ticks.idle += tickCount(info[base + Int(CPU_STATE_IDLE)])
            ticks.nice += tickCount(info[base + Int(CPU_STATE_NICE)])
        }
        return ticks
    }

    public func gpuUsage() -> Double? { sensors.gpuUsage() }

    public func memory() -> MemoryStats {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemoryStats(usedBytes: 0, totalBytes: total, pressure: .normal)
        }
        let page = UInt64(max(1, sysconf(_SC_PAGESIZE)))
        let usedPages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return MemoryStats(usedBytes: min(total, usedPages * page), totalBytes: total, pressure: Self.memoryPressure())
    }

    public func networkCounters() -> NetworkCounters {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else {
            return NetworkCounters(bytesIn: 0, bytesOut: 0)
        }
        defer { freeifaddrs(addresses) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let flags = Int32(entry.pointee.ifa_flags)
            if let address = entry.pointee.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
               let data = entry.pointee.ifa_data {
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(counters.ifi_ibytes)
                sent += UInt64(counters.ifi_obytes)
            }
            cursor = entry.pointee.ifa_next
        }
        return NetworkCounters(bytesIn: received, bytesOut: sent)
    }

    public func disk() -> DiskStats {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return DiskStats(freeBytes: 0, totalBytes: 0)
        }
        let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
        let free = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
        return DiskStats(freeBytes: free, totalBytes: total)
    }

    /// Returns nil on Macs without an internal battery (e.g. Mac mini).
    public func battery() -> BatteryStats? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery",
                  let current = description["Current Capacity"] as? Int,
                  let maximum = description["Max Capacity"] as? Int, maximum > 0 else { continue }
            let charging = description["Is Charging"] as? Bool ?? false
            var minutes: Int?
            if let value = description[charging ? "Time to Full Charge" : "Time to Empty"] as? Int, value >= 0 {
                minutes = value
            }
            return BatteryStats(level: min(1, Double(current) / Double(maximum)), isCharging: charging,
                                watts: nil, minutesRemaining: minutes)
        }
        return nil
    }

    public func temperatures() -> [String: Double] { sensors.temperatures() }

    private static func memoryPressure() -> MemoryStats.Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}

/// Reads a C string buffer up to its first zero byte.
private func text(from buffer: [CChar]) -> String {
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

/// Every IPv4 address the machine has, with the interface it belongs to.
public func systemLocalAddresses() -> [(interface: String, address: String)] {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return [] }
    defer { freeifaddrs(head) }
    var result: [(interface: String, address: String)] = []
    var pointer: UnsafeMutablePointer<ifaddrs>? = first
    while let current = pointer {
        defer { pointer = current.pointee.ifa_next }
        guard let addressPointer = current.pointee.ifa_addr,
              addressPointer.pointee.sa_family == UInt8(AF_INET) else { continue }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(addressPointer, socklen_t(addressPointer.pointee.sa_len), &buffer,
                          socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
        let address = text(from: buffer)
        let name = String(validatingCString: current.pointee.ifa_name) ?? ""
        if !address.isEmpty { result.append((interface: name, address: address)) }
    }
    return result
}

/// The busiest processes right now, read from `ps`.
public func systemTopProcesses(limit: Int) -> [ProcessUsage] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-Aco", "pid=,pcpu=,comm=", "-r"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do { try process.run() } catch { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return parseProcessUsage(String(decoding: data, as: UTF8.self), limit: limit,
                             excluding: ProcessInfo.processInfo.processIdentifier)
}
