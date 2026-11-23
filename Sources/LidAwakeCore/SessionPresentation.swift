import Foundation

/// A user-facing summary of why LidAwake is on, off, or asking for attention.
/// Kept in the core target so every state combination can be unit-tested
/// without launching the menu bar UI.
public struct SessionPresentation: Equatable, Sendable {
    /// "On", "Off", "Other" or "Ending".
    public var stateLabel: String
    /// Short status without the state prefix, e.g. "Running with the lid closed".
    public var statusText: String
    /// The complete status line for accessibility.
    public var headline: String
    /// One supporting sentence that explains the consequence or next step.
    public var subtitle: String
    public var modeShort: String
    /// Persistent explanation of the last automatic stop, until the next arm.
    public var eventNote: String?
    /// An active-session risk that has not crossed the stop threshold yet.
    public var riskNote: String?
    public var powerText: String
    public var thermalText: String
    public var lidText: String
    public var watchdogText: String
    public var isWarning: Bool
    public var isClamshellWarning: Bool
    public var isLowBattery: Bool
    public var isThermallyConstrained: Bool

    public init(
        stateLabel: String,
        statusText: String,
        headline: String,
        subtitle: String,
        modeShort: String,
        eventNote: String?,
        riskNote: String?,
        powerText: String,
        thermalText: String,
        lidText: String,
        watchdogText: String,
        isWarning: Bool,
        isClamshellWarning: Bool,
        isLowBattery: Bool,
        isThermallyConstrained: Bool
    ) {
        self.stateLabel = stateLabel
        self.statusText = statusText
        self.headline = headline
        self.subtitle = subtitle
        self.modeShort = modeShort
        self.eventNote = eventNote
        self.riskNote = riskNote
        self.powerText = powerText
        self.thermalText = thermalText
        self.lidText = lidText
        self.watchdogText = watchdogText
        self.isWarning = isWarning
        self.isClamshellWarning = isClamshellWarning
        self.isLowBattery = isLowBattery
        self.isThermallyConstrained = isThermallyConstrained
    }
}

/// The last event that ended a session. Shown until the next successful arm so
/// the panel always explains an automatic stop, even if it was closed at the time.
public struct DisarmEvent: Codable, Equatable, Sendable {
    public var reason: DisarmReason
    public var date: Date

    public init(reason: DisarmReason, date: Date = Date()) {
        self.reason = reason
        self.date = date
    }
}

public struct SessionPresentationInput: Sendable {
    public var isActive: Bool
    public var isStopping: Bool
    public var externalSession: Bool
    public var externalSessionStopping: Bool
    public var externalSleepDisabled: Bool
    public var errorMessage: String?
    public var mode: SleepMode
    public var tripMode: Bool
    public var hasSeenLidClosed: Bool
    public var lidClosed: Bool
    public var lidStateKnown: Bool
    public var sleepStateKnown: Bool
    public var clamshellCausesSleepKnown: Bool
    public var clamshellCausesSleep: Bool
    public var onAC: Bool
    public var charging: Bool
    public var batteryPercent: Int?
    public var batteryInfoKnown: Bool
    public var batteryFloor: Int
    public var thermalGuard: Bool
    public var thermalState: ProcessInfo.ThermalState
    public var watchdogHealthy: Bool
    public var watchdogLoaded: Bool
    public var lastEvent: DisarmEvent?

    public init(
        isActive: Bool,
        isStopping: Bool = false,
        externalSession: Bool = false,
        externalSessionStopping: Bool = false,
        externalSleepDisabled: Bool = false,
        errorMessage: String? = nil,
        mode: SleepMode = .clamshell,
        tripMode: Bool = true,
        hasSeenLidClosed: Bool = false,
        lidClosed: Bool = false,
        lidStateKnown: Bool = true,
        sleepStateKnown: Bool = true,
        clamshellCausesSleepKnown: Bool = true,
        clamshellCausesSleep: Bool = false,
        onAC: Bool = true,
        charging: Bool = false,
        batteryPercent: Int? = nil,
        batteryInfoKnown: Bool = true,
        batteryFloor: Int = 20,
        thermalGuard: Bool = true,
        thermalState: ProcessInfo.ThermalState = .nominal,
        watchdogHealthy: Bool = true,
        watchdogLoaded: Bool = true,
        lastEvent: DisarmEvent? = nil
    ) {
        self.isActive = isActive
        self.isStopping = isStopping
        self.externalSession = externalSession
        self.externalSessionStopping = externalSessionStopping
        self.externalSleepDisabled = externalSleepDisabled
        self.errorMessage = errorMessage
        self.mode = mode
        self.tripMode = tripMode
        self.hasSeenLidClosed = hasSeenLidClosed
        self.lidClosed = lidClosed
        self.lidStateKnown = lidStateKnown
        self.sleepStateKnown = sleepStateKnown
        self.clamshellCausesSleepKnown = clamshellCausesSleepKnown
        self.clamshellCausesSleep = clamshellCausesSleep
        self.onAC = onAC
        self.charging = charging
        self.batteryPercent = batteryPercent
        self.batteryInfoKnown = batteryInfoKnown
        self.batteryFloor = batteryFloor
        self.thermalGuard = thermalGuard
        self.thermalState = thermalState
        self.watchdogHealthy = watchdogHealthy
        self.watchdogLoaded = watchdogLoaded
        self.lastEvent = lastEvent
    }
}

public enum SessionPresentationBuilder {
    public static func make(_ input: SessionPresentationInput) -> SessionPresentation {
        let batteryUnavailable = !input.batteryInfoKnown ||
            (!input.onAC && input.batteryPercent == nil)
        let lowBattery = isLowBattery(input, batteryUnavailable: batteryUnavailable)
        let hot = input.thermalState == .serious || input.thermalState == .critical
        let thermalBlock = hot && input.thermalGuard
        let clamshellWarning = input.isActive &&
            input.mode == .clamshell &&
            input.lidStateKnown && input.lidClosed &&
            input.clamshellCausesSleepKnown &&
            input.clamshellCausesSleep
        let risk = riskNote(input)

        let stateLabel: String
        if input.externalSession {
            stateLabel = input.externalSessionStopping ? "Ending" : "Other"
        } else if input.isStopping {
            stateLabel = "Ending"
        } else {
            stateLabel = input.isActive ? "On" : "Off"
        }

        let statusText: String
        let subtitle: String
        if input.externalSession {
            if input.externalSessionStopping {
                statusText = "A previous session is restoring sleep"
                subtitle = "LidAwake is waiting for the safety check to finish."
            } else {
                statusText = "Another session is active"
                subtitle = "Turn it off there before using this one."
            }
        } else if input.isStopping {
            statusText = "Restoring normal sleep"
            subtitle = "The safety check is restoring normal sleep."
        } else if input.isActive {
            if input.mode == .system {
                if input.sleepStateKnown {
                    statusText = "All sleep is blocked"
                    subtitle = "Idle and lid-close sleep are blocked."
                } else {
                    statusText = "Sleep state unavailable"
                    subtitle = "LidAwake is checking the system-wide flag."
                }
            } else if clamshellWarning {
                statusText = "Lid-close sleep may not be blocked"
                subtitle = "macOS still reports lid-close sleep."
            } else if !input.lidStateKnown {
                statusText = "Lid status unavailable"
                subtitle = "Keep the lid open if the Mac needs to stay awake."
            } else if input.lidClosed {
                statusText = "Running with the lid closed"
                subtitle = "Lid-close sleep is blocked. Keep the Mac ventilated."
            } else if input.tripMode {
                statusText = "Close the lid to keep working"
                subtitle = input.hasSeenLidClosed
                    ? "Opening the lid will turn it off."
                    : "Close the lid once; reopening it will then stop the session."
            } else {
                statusText = "Lid-close sleep is blocked"
                subtitle = "It turns off when the timer ends."
            }
        } else if input.externalSleepDisabled {
            statusText = "Sleep is already off"
            subtitle = "Sleep was disabled outside LidAwake."
        } else if input.mode == .system && !input.sleepStateKnown {
            statusText = "Sleep state unavailable"
            subtitle = "All sleep mode can't be verified right now."
        } else if batteryUnavailable {
            statusText = "Battery state unavailable"
            subtitle = "LidAwake won't start without a battery reading."
        } else if lowBattery {
            statusText = "Battery is below your limit"
            subtitle = "Charge above \(input.batteryFloor)% or lower the limit."
        } else if thermalBlock {
            statusText = "The Mac is too hot to start"
            subtitle = "Let it cool, then try again."
        } else {
            statusText = "Normal sleep"
            subtitle = "Your Mac sleeps when you close the lid."
        }

        return SessionPresentation(
            stateLabel: stateLabel,
            statusText: statusText,
            headline: "\(stateLabel) · \(statusText)",
            subtitle: subtitle,
            modeShort: input.mode == .system ? "All sleep" : "Lid close",
            eventNote: eventNote(input),
            riskNote: risk,
            powerText: powerText(input, batteryUnavailable: batteryUnavailable),
            thermalText: thermalText(input.thermalState),
            lidText: input.lidStateKnown ? (input.lidClosed ? "Lid closed" : "Lid open") : "Lid unknown",
            watchdogText: input.watchdogHealthy
                ? "Active"
                : (input.watchdogLoaded ? "Not responding" : "Not installed"),
            isWarning: input.externalSession ||
                input.externalSleepDisabled ||
                batteryUnavailable ||
                (input.mode == .system && !input.sleepStateKnown) ||
                clamshellWarning ||
                (input.isActive && input.mode == .clamshell && !input.lidStateKnown) ||
                lowBattery ||
                thermalBlock ||
                !input.watchdogHealthy ||
                risk != nil ||
                (input.errorMessage != nil && (input.isActive || input.isStopping)),
            isClamshellWarning: clamshellWarning,
            isLowBattery: lowBattery,
            isThermallyConstrained: hot
        )
    }

    private static func isLowBattery(
        _ input: SessionPresentationInput,
        batteryUnavailable: Bool
    ) -> Bool {
        guard !batteryUnavailable else { return false }
        guard !input.onAC, !input.charging else { return false }
        guard let percent = input.batteryPercent else { return false }
        return percent <= input.batteryFloor
    }

    private static func riskNote(_ input: SessionPresentationInput) -> String? {
        guard input.isActive else { return nil }
        if !input.onAC, !input.charging {
            if let percent = input.batteryPercent, percent <= input.batteryFloor + 5 {
                return "Battery at \(percent)%; this session stops at \(input.batteryFloor)%."
            }
            if input.batteryPercent == nil {
                return "The battery can't be read; this session may stop."
            }
        }
        if input.thermalGuard,
           input.thermalState == .serious || input.thermalState == .critical {
            return "The Mac is warm; this session may stop."
        }
        return nil
    }

    private static func powerText(
        _ input: SessionPresentationInput,
        batteryUnavailable: Bool
    ) -> String {
        if batteryUnavailable { return "Battery unknown" }
        if input.charging {
            return input.batteryPercent.map { "\($0)% · Charging" } ?? "Charging"
        }
        if input.onAC {
            return input.batteryPercent.map { "\($0)% · AC" } ?? "AC power"
        }
        return input.batteryPercent.map { "\($0)% · Battery" } ?? "Battery unknown"
    }

    private static func thermalText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private static func eventNote(_ input: SessionPresentationInput) -> String? {
        guard !input.isActive, !input.isStopping, !input.externalSession,
              let event = input.lastEvent else {
            return nil
        }
        switch event.reason {
        case .timer:
            return "Last session ended when the timer finished."
        case .battery:
            return "Last session ended at the battery limit."
        case .thermal:
            return "Last session ended because the Mac got hot."
        case .lidOpened:
            return "Last session ended when the lid opened."
        case .watchdog:
            return "Last session ended by the safety check."
        case .error:
            return "Last session ended after a safety check failed."
        case .loginItemDisabled:
            return "Last session ended because Open at Login was disabled."
        case .user, .appQuit:
            return nil
        }
    }
}
