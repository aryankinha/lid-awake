enum WakeControlState: Equatable {
    case off, on, blocked, busy, restoring, external

    init(isActive: Bool, isRestoring: Bool, isExternal: Bool, isBusy: Bool, isArmBlocked: Bool) {
        if isRestoring {
            self = .restoring
        } else if isExternal {
            self = .external
        } else if isBusy {
            self = .busy
        } else if isActive {
            self = .on
        } else {
            self = isArmBlocked ? .blocked : .off
        }
    }

    var requestedActive: Bool? {
        switch self {
        case .off: return true
        case .on: return false
        case .blocked, .busy, .restoring, .external: return nil
        }
    }

    var actionTitle: String {
        switch self {
        case .off, .blocked: return "Turn On"
        case .on: return "Turn Off"
        case .busy: return "Working…"
        case .restoring: return "Restoring Sleep…"
        case .external: return "Managed Elsewhere"
        }
    }

    func sessionValue(remaining: String?) -> String {
        switch self {
        case .off, .blocked: return "Off"
        case .on: return remaining ?? "On"
        case .busy: return "Waiting"
        case .restoring: return "Ending"
        case .external: return "External"
        }
    }
}
