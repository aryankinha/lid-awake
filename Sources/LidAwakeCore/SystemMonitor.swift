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
        let sleepDisabled = boolProperty("SleepDisabled")
        let lidClosed = boolProperty("AppleClamshellState")
        let causesSleep = boolProperty("AppleClamshellCausesSleep")
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
            batteryInfoKnown: battery.known
        )
    }

    public func setClamshellOverride(_ enabled: Bool) throws {
        try clamshell.setClamshellSleepDisabled(enabled)
    }

    public func setSystemSleepDisabled(_ enabled: Bool) throws {
        try pmset.setSystemSleepDisabled(enabled)
    }

    private func boolProperty(_ key: String) -> Bool? {
        guard let matching = IOServiceMatching("IOPMrootDomain") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

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

    private struct BatteryReading {
        var onAC: Bool
        var percent: Int?
        var charging: Bool
        var known: Bool
    }

    private func readBattery() -> BatteryReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryReading(onAC: true, percent: nil, charging: false, known: false)
        }

        var onAC = true
        var percent: Int?
        var charging = false
        var known = false

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }
            guard (description[kIOPSIsPresentKey] as? Bool) ?? true else {
                continue
            }

            let state = description[kIOPSPowerSourceStateKey] as? String
            let type = description[kIOPSTypeKey] as? String
            let isBattery = type == kIOPSInternalBatteryType ||
                (description[kIOPSCurrentCapacityKey] != nil && description[kIOPSMaxCapacityKey] != nil)

            if state == kIOPSBatteryPowerValue {
                onAC = false
            } else if state == kIOPSACPowerValue {
                onAC = true
            }

            // Capture the battery percentage even while on AC. The source
            // state is "AC Power" when plugged in, so checking for
            // "Battery Power" alone would make the battery guard fail open.
            if isBattery {
                known = true
                percent = description[kIOPSCurrentCapacityKey] as? Int
                charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            }
        }

        return BatteryReading(onAC: onAC, percent: percent, charging: charging, known: known)
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
