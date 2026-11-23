import Foundation
import IOKit
import IOKit.ps

public protocol SystemControlling: AnyObject {
    func snapshot() -> SystemSnapshot
    func setClamshellOverride(_ enabled: Bool) throws
    func setSystemSleepDisabled(_ enabled: Bool) throws
}

/// Reads the live kernel/power state without shelling out.
public final class IOKitSystemMonitor: SystemControlling {
    private let clamshell = ClamshellSelector()
    private let pmset = PmsetController()

    public init() {}

    public func snapshot() -> SystemSnapshot {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { if root != IO_OBJECT_NULL { IOObjectRelease(root) } }
        let sleepDisabled = boolProperty("SleepDisabled", service: root)
        let lidClosed = boolProperty("AppleClamshellState", service: root)
        let causesSleep = boolProperty("AppleClamshellCausesSleep", service: root)
        let battery = readBattery()

        return SystemSnapshot(
            sleepDisabled: sleepDisabled ?? false,
            lidClosed: lidClosed ?? false,
            clamshellCausesSleep: causesSleep ?? false,
            onAC: battery.onAC,
            batteryPercent: battery.percent,
            charging: battery.charging,
            thermalState: ProcessInfo.processInfo.thermalState,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            clamshellCausesSleepKnown: causesSleep != nil,
            sleepDisabledKnown: sleepDisabled != nil,
            batteryInfoKnown: battery.known,
            lidStateKnown: lidClosed != nil
        )
    }

    public func setClamshellOverride(_ enabled: Bool) throws {
        try clamshell.setClamshellSleepDisabled(enabled)
    }

    public func setSystemSleepDisabled(_ enabled: Bool) throws {
        try pmset.setSystemSleepDisabled(enabled)
    }

    private func boolProperty(_ key: String, service: io_service_t) -> Bool? {
        guard service != IO_OBJECT_NULL else { return nil }
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return value as? Bool
    }

    private func readBattery() -> BatteryReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unknown
        }
        return BatteryReading.read(sources.lazy.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        })
    }
}

struct BatteryReading: Equatable {
    let onAC: Bool
    let percent: Int?
    let charging: Bool
    let known: Bool

    static let unknown = BatteryReading(onAC: true, percent: nil, charging: false, known: false)

    static func read(_ sources: some Sequence<[String: Any]>) -> BatteryReading {
        for source in sources {
            guard (source[kIOPSIsPresentKey] as? Bool) ?? true else { continue }

            let type = source[kIOPSTypeKey] as? String
            let transport = source[kIOPSTransportTypeKey] as? String
            guard type == kIOPSInternalBatteryType ||
                  (type == nil && transport == kIOPSInternalType) else { continue }

            let onAC: Bool
            switch source[kIOPSPowerSourceStateKey] as? String {
            case kIOPSACPowerValue: onAC = true
            case kIOPSBatteryPowerValue: onAC = false
            default: return .unknown
            }

            let percent: Int?
            if let current = source[kIOPSCurrentCapacityKey] as? Int, current >= 0,
               let maximum = source[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                percent = Int((Double(min(current, maximum)) * 100 / Double(maximum)).rounded(.down))
            } else {
                percent = nil
            }

            return BatteryReading(
                onAC: onAC,
                percent: percent,
                charging: onAC && (source[kIOPSIsChargingKey] as? Bool ?? false),
                known: true
            )
        }
        return .unknown
    }
}

public enum SystemInfo {
    public static var bootID: String {
        var value = timeval()
        var size = MemoryLayout<timeval>.stride
        let result = sysctlbyname("kern.boottime", &value, &size, nil, 0)
        guard result == 0 else { return "unknown" }
        return "\(value.tv_sec):\(value.tv_usec)"
    }

    public static var processID: Int32 {
        ProcessInfo.processInfo.processIdentifier
    }

    public static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
