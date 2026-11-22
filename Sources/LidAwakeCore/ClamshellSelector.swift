import Foundation
import IOKit

/// Controls Apple's private clamshell-sleep selector.
///
/// `kPMSetClamshellSleepState` (selector 12) is present in Apple's SDK and xnu
/// source. In the shipping kernel it sets the `kClamshellSleepDisablePowerd`
/// bit on `IOPMrootDomain`. Unlike `pmset disablesleep`, it only suppresses
/// lid-close sleep; idle sleep, low-battery sleep and thermal sleep continue
/// to work.
///
/// This is an undocumented/private API. It is used only after the app has
/// verified that the call succeeds, and the app keeps a `pmset` fallback.
public final class ClamshellSelector {
    /// Selector from `IOPMLibDefs.h`.
    public static let selector: UInt32 = 12

    public init() {}

    /// Enable or disable the clamshell-sleep override.
    ///
    /// The call is intentionally one-shot: the kernel keeps the bit set after
    /// the IOKit connection closes, so the watchdog can clear it independently.
    public func setClamshellSleepDisabled(_ disabled: Bool) throws {
        guard let matching = IOServiceMatching("IOPMrootDomain") else {
            throw LidAwakeError.ioKitServiceUnavailable
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            throw LidAwakeError.ioKitServiceUnavailable
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == KERN_SUCCESS else {
            throw LidAwakeError.ioKitOpenFailed(openResult)
        }
        defer { IOServiceClose(connection) }

        var input: UInt64 = disabled ? 1 : 0
        let result = IOConnectCallScalarMethod(
            connection,
            Self.selector,
            &input,
            1,
            nil,
            nil
        )
        guard result == KERN_SUCCESS else {
            throw LidAwakeError.clamshellSelectorFailed(result)
        }
    }
}
