import Foundation
import LidAwakeCore

private let monitor = IOKitSystemMonitor()
private let store = FileLeaseStore()

private func json<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

private struct StatusPayload: Codable {
    var sleepDisabled: Bool
    var sleepDisabledKnown: Bool
    var lidClosed: Bool
    var lidStateKnown: Bool
    var clamshellCausesSleep: Bool
    var clamshellCausesSleepKnown: Bool
    var onAC: Bool
    var batteryPercent: Int?
    var batteryInfoKnown: Bool
    var charging: Bool
    var thermalState: Int
    var lowPowerMode: Bool
    var lease: SessionLease?
    var watchdogHealth: WatchdogHealth?
    var watchdogLoaded: Bool
}

private func snapshotPayload() -> StatusPayload {
    let snapshot = monitor.snapshot()
    let installer = WatchdogInstaller(store: store)
    return StatusPayload(
        sleepDisabled: snapshot.sleepDisabled,
        sleepDisabledKnown: snapshot.sleepDisabledKnown,
        lidClosed: snapshot.lidClosed,
        lidStateKnown: snapshot.lidStateKnown,
        clamshellCausesSleep: snapshot.clamshellCausesSleep,
        clamshellCausesSleepKnown: snapshot.clamshellCausesSleepKnown,
        onAC: snapshot.onAC,
        batteryPercent: snapshot.batteryPercent,
        batteryInfoKnown: snapshot.batteryInfoKnown,
        charging: snapshot.charging,
        thermalState: snapshot.thermalState.rawValue,
        lowPowerMode: snapshot.lowPowerMode,
        lease: try? store.load(),
        watchdogHealth: try? store.loadHealth(),
        watchdogLoaded: installer.isLoaded
    )
}

private func printStatus() {
    let payload = snapshotPayload()
    print("LidAwake status")
    print("  sleepDisabled:        \(payload.sleepDisabledKnown ? "\(payload.sleepDisabled)" : "unknown")")
    print("  lidClosed:            \(payload.lidStateKnown ? "\(payload.lidClosed)" : "unknown")")
    print("  clamshellCausesSleep: \(payload.clamshellCausesSleepKnown ? "\(payload.clamshellCausesSleep)" : "unknown")")
    print("  power:                \(payload.onAC ? "AC" : "Battery") \(payload.batteryPercent.map { "\($0)%" } ?? "n/a")\(payload.batteryInfoKnown ? "" : " (unknown)")")
    print("  charging:             \(payload.charging)")
    print("  thermalState:         \(payload.thermalState)")
    print("  lease:                \(payload.lease == nil ? "none" : "present")")
    print("  watchdogLoaded:       \(payload.watchdogLoaded)")
    if let lease = payload.lease {
        print("  lease.mode:           \(lease.mode.rawValue)")
        print("  lease.deadline:       \(lease.deadline.map { ISO8601DateFormatter().string(from: $0) } ?? "none")")
        print("  lease.updatedAt:      \(ISO8601DateFormatter().string(from: lease.updatedAt))")
    }
}

private func usage() -> Never {
    print("""
    usage: lidawake-ctl <command>

      status [--json]        Read live sleep/lid/battery/thermal state
      clamshell on|off       Set or clear the private clamshell override
      probe [--json]         Set/clear the override and print state transitions
      arm [options]          Start a session and hold it until it auto-ends
      disarm                 Clear the current session/override
      watchdog               Run the safety watchdog loop
      install-watchdog       Install the user LaunchAgent from this executable
      uninstall-watchdog     Remove the user LaunchAgent and copied helper
      install-login <app>    Install the app login LaunchAgent
      uninstall-login        Remove the app login LaunchAgent
      help                   Show this help

    arm options:
      --minutes N            Auto-off after N minutes (default 120)
      --mode clamshell|system
      --trip / --no-trip     Trip Mode (default on)
      --battery-floor N      Battery floor (default 20)
      --no-thermal           Disable the thermal guard
    """)
    exit(64)
}

private func requireClamshellArg(_ args: [String]) -> Bool {
    guard args.count >= 2 else { usage() }
    switch args[1] {
    case "on", "1", "true": return true
    case "off", "0", "false": return false
    default: usage()
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }

switch command {
case "status":
    if arguments.contains("--json") {
        print(json(snapshotPayload()))
    } else {
        printStatus()
    }

case "clamshell":
    let enabled = requireClamshellArg(arguments)
    do {
        try monitor.setClamshellOverride(enabled)
        print("clamshell override \(enabled ? "ON" : "OFF")")
        let after = monitor.snapshot()
        print("sleepDisabled=\(after.sleepDisabled) lidClosed=\(after.lidClosed) clamshellCausesSleep=\(after.clamshellCausesSleep)")
    } catch {
        fputs("error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case "probe":
    let before = monitor.snapshot()
    do {
        defer { try? monitor.setClamshellOverride(false) }
        try monitor.setClamshellOverride(true)
        Thread.sleep(forTimeInterval: 0.5)
        let on = monitor.snapshot()
        try monitor.setClamshellOverride(false)
        Thread.sleep(forTimeInterval: 0.5)
        let off = monitor.snapshot()

        let payload: [String: Any] = [
            "before": [
                "sleepDisabled": before.sleepDisabled,
                "lidClosed": before.lidClosed,
                "clamshellCausesSleep": before.clamshellCausesSleep,
            ],
            "afterOn": [
                "sleepDisabled": on.sleepDisabled,
                "lidClosed": on.lidClosed,
                "clamshellCausesSleep": on.clamshellCausesSleep,
            ],
            "afterOff": [
                "sleepDisabled": off.sleepDisabled,
                "lidClosed": off.lidClosed,
                "clamshellCausesSleep": off.clamshellCausesSleep,
            ],
        ]
        if arguments.contains("--json") {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("before:  sleepDisabled=\(before.sleepDisabled) lidClosed=\(before.lidClosed) clamshellCausesSleep=\(before.clamshellCausesSleep)")
            print("afterOn: sleepDisabled=\(on.sleepDisabled) lidClosed=\(on.lidClosed) clamshellCausesSleep=\(on.clamshellCausesSleep)")
            print("afterOff:sleepDisabled=\(off.sleepDisabled) lidClosed=\(off.lidClosed) clamshellCausesSleep=\(off.clamshellCausesSleep)")
        }
    } catch {
        fputs("error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case "arm":
    var minutes = 120.0
    var mode = SleepMode.clamshell
    var tripMode = true
    var batteryFloor = 20
    var thermalGuard = true
    var index = 1
    while index < arguments.count {
        switch arguments[index] {
        case "--minutes":
            index += 1
            guard index < arguments.count, let value = Double(arguments[index]),
                  value.isFinite, value >= 0 else { usage() }
            minutes = min(value, 480)
        case "--mode":
            index += 1
            guard index < arguments.count,
                  let value = SleepMode(rawValue: arguments[index]) else { usage() }
            mode = value
        case "--trip":
            tripMode = true
        case "--no-trip":
            tripMode = false
        case "--battery-floor":
            index += 1
            guard index < arguments.count, let value = Int(arguments[index]),
                  (10...50).contains(value) else { usage() }
            batteryFloor = value
        case "--no-thermal":
            thermalGuard = false
        default:
            usage()
        }
        index += 1
    }

    let installer = WatchdogInstaller(store: store)
    guard installer.isLoaded, installer.isHeartbeatFresh() else {
        fputs("error: safety watchdog is not healthy; run install.sh and retry\n", stderr)
        exit(1)
    }
    let controller = SessionController(system: monitor, leaseStore: store)
    let config = SessionConfig(
        mode: mode,
        duration: minutes * 60,
        batteryFloor: batteryFloor,
        tripMode: tripMode,
        thermalGuard: thermalGuard,
        maxDuration: 8 * 60 * 60
    )
    do {
        let session = try controller.arm(config: config)
        print("ARMED mode=\(session.mode.rawValue) trip=\(session.config.tripMode) floor=\(session.config.batteryFloor) deadline=\(session.deadline.map { ISO8601DateFormatter().string(from: $0) } ?? "none")")
        while true {
            if let reason = controller.tick() {
                print("AUTO-DISARM reason=\(reason.rawValue)")
                try controller.disarm(reason: reason)
                break
            }
            controller.renewLease()
            Thread.sleep(forTimeInterval: 5)
        }
    } catch {
        fputs("error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case "disarm":
    let lease: SessionLease?
    do {
        lease = try store.load()
    } catch {
        fputs("warning: corrupt lease; attempting full cleanup\n", stderr)
        lease = nil
    }
    var failures = 0
    do {
        try monitor.setClamshellOverride(false)
    } catch {
        failures += 1
        fputs("warning: clamshell clear failed: \(error.localizedDescription)\n", stderr)
    }
    if lease?.mode == .system && lease?.ownsPmset == true {
        do {
            try monitor.setSystemSleepDisabled(false)
            let after = monitor.snapshot()
            if !after.sleepDisabledKnown || after.sleepDisabled {
                failures += 1
                fputs("warning: pmset state is unknown or still on after clear\n", stderr)
            }
        } catch {
            failures += 1
            fputs("warning: pmset clear failed: \(error.localizedDescription)\n", stderr)
        }
    }
    if failures == 0 {
        try? store.save(nil)
        print("disarmed")
    } else {
        // Keep the lease so the watchdog can retry; do not claim success.
        fputs("error: one or more restore operations failed; lease retained for recovery\n", stderr)
        exit(1)
    }

case "watchdog":
    let runner = WatchdogRunner(leaseStore: store, system: monitor)
    runner.runForever()

case "install-watchdog":
    do {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        try WatchdogInstaller(store: store).install(helperSource: executable)
        print("watchdog installed")
    } catch {
        fputs("error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case "uninstall-watchdog":
    if WatchdogInstaller(store: store).uninstall() {
        print("watchdog removed")
    } else {
        fputs("error: watchdog did not exit; recovery retained\n", stderr)
        exit(1)
    }

case "install-login":
    guard arguments.count >= 2 else { usage() }
    do {
        try LoginItemInstaller().install(appPath: arguments[1])
        print("login item installed")
    } catch {
        fputs("error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case "uninstall-login":
    LoginItemInstaller().uninstall()
    print("login item removed")

case "help", "--help", "-h":
    usage()

default:
    usage()
}
