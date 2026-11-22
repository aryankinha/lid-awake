import Foundation
import Combine
import AppKit
import SwiftUI
@preconcurrency import LidAwakeCore

extension SleepMode: Identifiable {
    public var id: String { rawValue }
}

enum TimerPreset: String, CaseIterable, Identifiable {
    case off
    case oneHour
    case twoHours
    case fourHours
    case eightHours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "No limit (8h cap)"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .fourHours: return "4h"
        case .eightHours: return "8h"
        }
    }

    var shortTitle: String {
        switch self {
        case .off: return "None"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .fourHours: return "4h"
        case .eightHours: return "8h"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .off: return nil
        case .oneHour: return 3600
        case .twoHours: return 2 * 3600
        case .fourHours: return 4 * 3600
        case .eightHours: return 8 * 3600
        }
    }

    init(seconds: TimeInterval?) {
        guard let seconds else { self = .off; return }
        switch Int(seconds) {
        case 3600: self = .oneHour
        case 7200: self = .twoHours
        case 14400: self = .fourHours
        case 28800: self = .eightHours
        default: self = .twoHours
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var isActive = false
    @Published private(set) var activeSession: ActiveSession?
    @Published private(set) var externalLease: SessionLease?
    @Published private(set) var lastEvent: DisarmEvent?
    @Published private(set) var errorMessage: String? {
        didSet {
            if errorMessage != oldValue { syncMenuIcon() }
        }
    }
    @Published private(set) var watchdogHealthy = false
    @Published private(set) var watchdogLoaded = false
    @Published private(set) var externalSession = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var isBusy = false
    private(set) var terminationPrepared = false

    /// The MenuBarExtra label observes this tiny object, not AppModel. It only
    /// changes when the symbol or accessibility label actually changes.
    let menuIconModel = MenuBarIconModel()
    @Published var mode: SleepMode = .clamshell {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }
    @Published var timerPreset: TimerPreset = .twoHours {
        didSet {
            defaults.set(timerPreset.rawValue, forKey: Keys.timer)
            durationOverride = nil
        }
    }
    @Published var tripMode = true {
        didSet { defaults.set(tripMode, forKey: Keys.trip) }
    }
    @Published var batteryFloor = 20 {
        didSet { defaults.set(batteryFloor, forKey: Keys.batteryFloor) }
    }
    @Published var thermalGuard = true {
        didSet { defaults.set(thermalGuard, forKey: Keys.thermalGuard) }
    }

    private let defaults = UserDefaults.standard
    private let monitor = IOKitSystemMonitor()
    private let store: FileLeaseStore
    private let controller: SessionController
    private let watchdogInstaller: WatchdogInstaller
    private let loginItemInstaller = LoginItemInstaller()
    private let pmset = PmsetController()
    private let notifications = NotificationService()
    private let caffeinate = CaffeinateHelper()

    private var durationOverride: TimeInterval?
    private var uiTimer: Timer?
    private var leaseTimer: Timer?
    private var started = false
    private var lastDisarmAttempt: Date?
    private var watchdogMissCount = 0
    private var isDisarming = false
    private var wakeObserver: NSObjectProtocol?
    private var wakeGraceUntil: Date?
    private let workQueue = DispatchQueue(
        label: "com.aryankinha.LidAwake.actions",
        qos: .userInitiated
    )

    private enum Keys {
        static let mode = "mode"
        static let timer = "timer"
        static let trip = "tripMode"
        static let batteryFloor = "batteryFloor"
        static let thermalGuard = "thermalGuard"
    }

    init() {
        let store = FileLeaseStore()
        self.store = store
        self.controller = SessionController(system: monitor, leaseStore: store)
        self.watchdogInstaller = WatchdogInstaller(store: store)

        if let raw = defaults.string(forKey: Keys.mode), let mode = SleepMode(rawValue: raw) {
            self.mode = mode
        }
        if let raw = defaults.string(forKey: Keys.timer), let preset = TimerPreset(rawValue: raw) {
            self.timerPreset = preset
        }
        if defaults.object(forKey: Keys.trip) != nil {
            self.tripMode = defaults.bool(forKey: Keys.trip)
        }
        if defaults.object(forKey: Keys.batteryFloor) != nil {
            self.batteryFloor = min(max(defaults.integer(forKey: Keys.batteryFloor), 10), 50)
        }
        if defaults.object(forKey: Keys.thermalGuard) != nil {
            self.thermalGuard = defaults.bool(forKey: Keys.thermalGuard)
        }

        self.snapshot = monitor.snapshot()
        self.launchAtLogin = loginItemInstaller.isInstalled
        self.watchdogLoaded = watchdogInstaller.isLoaded
    }

    func start() {
        guard !started else { return }
        started = true
        notifications.requestAuthorization()
        // Keep an already-loaded watchdog; force-reinstalling deletes its health
        // file and can flash a false triangle on every app launch.
        ensureWatchdog()
        let loaded = watchdogInstaller.isLoaded
        if loaded != watchdogLoaded { watchdogLoaded = loaded }
        if loginItemInstaller.isConfigured && !loginItemInstaller.isInstalled {
            loginItemInstaller.uninstall()
        }
        refreshLaunchAtLogin()
        recoverStaleSessionAtLaunch()
        refresh()

        uiTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let uiTimer { RunLoop.main.add(uiTimer, forMode: .common) }

        leaseTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renew() }
        }
        if let leaseTimer { RunLoop.main.add(leaseTimer, forMode: .common) }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.watchdogMissCount = 0
                self.wakeGraceUntil = Date().addingTimeInterval(20)
                self.refresh()
            }
        }
    }

    /// Re-read the login item in case it changed in System Settings while the
    /// app was running. Runs off the main thread so opening the panel stays
    /// responsive.
    func refreshLaunchAtLogin() {
        guard !isBusy else { return }
        let installer = loginItemInstaller
        workQueue.async {
            let installed = installer.isInstalled
            Task { @MainActor in
                guard !self.isBusy else { return }
                if installed != self.launchAtLogin {
                    self.launchAtLogin = installed
                }
            }
        }
    }

    func setActive(_ active: Bool) {
        guard !isBusy else { return }
        if active {
            arm()
        } else {
            disarm(reason: .user)
        }
    }

    func arm() {
        guard !isActive, !isBusy else { return }
        guard !externalSession else {
            errorMessage = "Another LidAwake session is active. Turn it off there first."
            return
        }
        clearError()

        // Consume any URL-specific duration now. An early preflight failure must
        // never leave a hidden override that applies to a later normal turn-on.
        let requestedDuration = durationOverride ?? timerPreset.seconds
        durationOverride = nil
        if let requestedDuration, !requestedDuration.isFinite || requestedDuration < 0 {
            errorMessage = "The requested session duration is invalid."
            return
        }

        if externalSleepDisabled {
            errorMessage = "Sleep is already off outside LidAwake. Clear it before starting."
            return
        }

        ensureWatchdog()
        guard watchdogInstaller.isLoaded, watchdogInstaller.isHeartbeatFresh() else {
            errorMessage = "The safety check isn't running yet. Use Repair in the notice, wait a moment, and try again."
            return
        }

        if mode == .system && !pmset.isGrantInstalled {
            errorMessage = "All sleep mode needs a one-time setup. Use Set Up in Advanced first."
            return
        }

        let preflight = monitor.snapshot()
        guard preflight.batteryInfoKnown else {
            errorMessage = "The battery can't be read. For safety, LidAwake won't turn on without a battery reading."
            return
        }
        if !preflight.onAC, !preflight.charging {
            guard let percent = preflight.batteryPercent else {
                errorMessage = "The battery percentage can't be read. For safety, LidAwake won't turn on."
                return
            }
            if percent <= batteryFloor {
                errorMessage = "Battery is at \(percent)%, at or below your \(batteryFloor)% limit."
                return
            }
        }
        if thermalGuard, preflight.thermalState == .serious || preflight.thermalState == .critical {
            errorMessage = "The Mac is too hot to start. Let it cool, then try again."
            return
        }
        if mode == .system && !preflight.sleepDisabledKnown {
            errorMessage = "Sleep state is unavailable, so All sleep mode can't be verified."
            return
        }
        if mode == .system && preflight.sleepDisabled {
            errorMessage = "Sleep is already off outside LidAwake. Clear it before using All sleep."
            return
        }

        let config = SessionConfig(
            mode: mode,
            duration: requestedDuration,
            batteryFloor: batteryFloor,
            tripMode: tripMode,
            thermalGuard: thermalGuard,
            maxDuration: 8 * 60 * 60
        )

        guard let helperPID = caffeinate.start() else {
            errorMessage = "The idle-sleep helper didn't start. Try again."
            return
        }

        do {
            let session = try controller.arm(config: config, helperPID: helperPID)
            activeSession = session
            isActive = true
            lastEvent = nil
            watchdogMissCount = 0
            notifications.notify(title: "LidAwake is ON", body: armMessage(config: config))
            refresh()
        } catch {
            caffeinate.stop()
            errorMessage = error.localizedDescription
            refresh()
        }
    }

    func disarm(reason: DisarmReason) {
        guard controller.active != nil else {
            caffeinate.stop()
            refresh()
            return
        }
        guard !isDisarming else { return }
        isDisarming = true
        do {
            try controller.disarm(reason: reason)
            isActive = false
            activeSession = nil
            durationOverride = nil
            errorMessage = nil
            caffeinate.stop()
            if reason != .user && reason != .appQuit {
                lastEvent = DisarmEvent(reason: reason)
            }
            notifications.notify(title: "LidAwake is OFF", body: reason.displayName)
        } catch {
            // The session is still active; keep the idle-sleep helper running
            // so a failed restore does not silently weaken the session.
            errorMessage = "Couldn't restore normal sleep: \(error.localizedDescription). The safety check will retry."
        }
        isDisarming = false
        refresh()
    }

    func clearExternalSleepFlag() {
        guard !isActive else {
            errorMessage = "Turn LidAwake off before clearing the outside sleep setting."
            return
        }
        guard !externalSession else {
            errorMessage = "Another LidAwake session owns the sleep state. Turn it off there first."
            return
        }
        guard !isBusy else { return }

        isBusy = true
        errorMessage = nil
        let pmset = self.pmset
        workQueue.async {
            var failure: String?
            do {
                try pmset.clearSystemFlagWithAuthorization()
            } catch {
                failure = error.localizedDescription
            }
            Task { @MainActor in
                self.isBusy = false
                if let failure {
                    self.errorMessage = failure
                } else {
                    self.notifications.notify(
                        title: "System sleep flag cleared",
                        body: "LidAwake can manage sleep again."
                    )
                }
                self.refresh()
            }
        }
    }

    func repairWatchdog() {
        guard !isBusy else { return }
        guard let helper = Bundle.main.resourceURL?.appendingPathComponent("lidawake-ctl"),
              FileManager.default.fileExists(atPath: helper.path) else {
            errorMessage = "The safety helper is missing from the app bundle."
            return
        }

        isBusy = true
        errorMessage = nil
        let installer = watchdogInstaller
        workQueue.async {
            var failure: String?
            do {
                try installer.install(helperSource: helper)
            } catch {
                failure = error.localizedDescription
            }
            Task { @MainActor in
                self.isBusy = false
                self.watchdogMissCount = 0
                let loaded = installer.isLoaded
                if loaded != self.watchdogLoaded { self.watchdogLoaded = loaded }
                if let failure {
                    self.errorMessage = "Couldn't repair the safety check: \(failure)"
                }
                self.refresh()
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isBusy, enabled != launchAtLogin else { return }

        launchAtLogin = enabled
        isBusy = true
        errorMessage = nil
        let installer = loginItemInstaller
        let appPath = Bundle.main.bundlePath
        workQueue.async {
            var failure: String?
            do {
                if enabled {
                    try installer.install(appPath: appPath)
                } else {
                    installer.uninstall()
                }
            } catch {
                installer.uninstall()
                failure = error.localizedDescription
            }
            Task { @MainActor in
                self.isBusy = false
                self.launchAtLogin = installer.isInstalled
                if let failure {
                    self.errorMessage = "Couldn't update Open at Login: \(failure)"
                }
            }
        }
    }

    func handle(_ urls: [URL]) {
        for url in urls where url.scheme == "lidawake" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let query = Dictionary((components?.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }, uniquingKeysWith: { _, last in last })

            switch url.host {
            case "on", "arm":
                guard !isActive else { continue }
                if let minutes = query["minutes"].flatMap(Double.init), minutes.isFinite {
                    if minutes <= 0 {
                        timerPreset = .off
                    } else {
                        durationOverride = min(minutes, 8 * 60) * 60
                    }
                }
                if query["trip"] == "0" { tripMode = false }
                if query["trip"] == "1" { tripMode = true }
                if let rawMode = query["mode"], let parsed = SleepMode(rawValue: rawMode) {
                    mode = parsed
                }
                arm()
            case "off", "disarm":
                if isActive { disarm(reason: .user) }
                durationOverride = nil
            case "toggle":
                setActive(!isActive)
            case "status", "diagnostics":
                // The popover may be closed; copy diagnostics so the URL is
                // useful in a menu bar overflow / headless situation.
                copyDiagnostics()
                notifications.notify(title: "LidAwake diagnostics copied", body: "The status JSON is on the clipboard.")
            case "quit", "exit":
                quit()
            case "render":
                // Developer-only capture path. Normal launches do not inherit
                // this variable, so the render URL is inert in release use.
                guard ProcessInfo.processInfo.environment["LIDAWAKE_RENDER"] == "1" else {
                    break
                }
                renderPreview(
                    showAdvanced: query["advanced"] == "1",
                    appearance: query["light"] == "1" ? .aqua : .darkAqua
                )
            default:
                break
            }
        }
    }

    /// Cleans runtime state on a normal quit. The app bundle, UserDefaults and an
    /// explicitly enabled Launch at login item are intentional installation
    /// artifacts and are preserved; the watchdog, helper, lease, heartbeat and
    /// logs are removed.
    @discardableResult
    func shutdown(clean: Bool = false) -> Bool {
        guard !isBusy else {
            errorMessage = "Wait for the current safety action to finish before quitting."
            return false
        }

        if controller.active != nil {
            do {
                try controller.disarm(reason: .appQuit)
                isActive = false
                activeSession = nil
                lastEvent = nil
            } catch {
                // Leave the helper running: the session is still active and
                // quit was cancelled.
                errorMessage = "Couldn't restore normal sleep; quit cancelled. The safety check will retry."
                return false
            }
        } else {
            let lease: SessionLease?
            do {
                lease = try store.load()
            } catch {
                errorMessage = "The session record can't be read, so quit was cancelled to avoid losing recovery."
                return false
            }
            if let lease, lease.bootID == SystemInfo.bootID {
                let foreign = lease.pid != SystemInfo.processID
                let live = foreign && SystemInfo.processIsAlive(lease.pid)
                if live {
                    // Never destroy another process's live safety state.
                    errorMessage = "Another LidAwake session is active. Turn it off there before quitting."
                    return false
                }
                if lease.stopping {
                    // A stopping lease means a restore is still pending, even if
                    // the owning process has exited. Leave the watchdog and lease.
                    errorMessage = "Another session is still restoring normal sleep. Try quitting again in a moment."
                    return false
                }
            }
        }

        caffeinate.stop()
        guard clean else { return true }

        guard watchdogInstaller.uninstall() else {
            errorMessage = "The safety check didn't stop; quit cancelled to avoid removing recovery halfway."
            return false
        }
        uiTimer?.invalidate()
        leaseTimer?.invalidate()
        uiTimer = nil
        leaseTimer = nil
        store.clearAll()
        return true
    }

    func prepareForTermination() {
        terminationPrepared = true
    }

    func quit() {
        guard shutdown(clean: true) else { return }
        prepareForTermination()
        NSApplication.shared.terminate(nil)
    }

    /// Local design/debug helper: hosts the real SwiftUI view in an offscreen
    /// window so AppKit controls and scroll layout are captured, not the yellow
    /// placeholders produced by ImageRenderer.
    private func renderPreview(
        showAdvanced: Bool,
        appearance: NSAppearance.Name
    ) {
        final class HeightBox {
            var value: CGFloat = 0
        }
        let box = HeightBox()
        let view = MenuBarView(
            model: self,
            onSizeChange: { box.value = $0 },
            showAdvanced: showAdvanced
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: Theme.panelWidth,
            height: showAdvanced ? 760 : 620
        )

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = appearance == .darkAqua
            ? NSColor(calibratedWhite: 0.10, alpha: 1)
            : NSColor(calibratedWhite: 0.96, alpha: 1)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        if box.value > 100 {
            hosting.frame.size.height = box.value
            window.setContentSize(NSSize(width: Theme.panelWidth, height: box.value))
        }
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(hosting.bounds.width * scale),
            pixelsHigh: Int(hosting.bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            notifications.notify(title: "LidAwake", body: "Could not render the UI preview.")
            window.orderOut(nil)
            return
        }
        rep.size = hosting.bounds.size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            notifications.notify(title: "LidAwake", body: "Could not encode the UI preview.")
            window.orderOut(nil)
            return
        }

        let mode = showAdvanced ? "advanced" : "collapsed"
        let look = appearance == .darkAqua ? "dark" : "light"
        let urls = [
            URL(fileURLWithPath: "/tmp/lidawake-ui-\(look)-\(mode).png"),
            URL(fileURLWithPath: "/tmp/lidawake-ui-render.png")
        ]
        for url in urls {
            try? png.write(to: url)
        }
        window.orderOut(nil)
    }

    func copyDiagnostics() {
        let text = diagnosticsText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    var isStopping: Bool {
        controller.stopping
    }

    /// True when the panel should not offer to start a session. The primary
    /// status already explains the current blocker, so the switch is disabled
    /// instead of allowing a click that cannot succeed.
    var isArmBlocked: Bool {
        guard !isActive else { return false }
        if externalSession || !watchdogHealthy || externalSleepDisabled { return true }
        if presentation.isLowBattery { return true }
        if thermalGuard && presentation.isThermallyConstrained { return true }
        if !snapshot.batteryInfoKnown { return true }
        if !snapshot.onAC && snapshot.batteryPercent == nil { return true }
        if mode == .system {
            if !fallbackInstalled { return true }
            if !snapshot.sleepDisabledKnown || snapshot.sleepDisabled { return true }
        }
        return false
    }

    var menuIcon: String {
        if isStopping || externalSession || !watchdogHealthy || externalSleepDisabled {
            return "exclamationmark.triangle.fill"
        }
        if errorMessage != nil { return "exclamationmark.triangle.fill" }
        return isActive ? "sun.max.fill" : "moon.fill"
    }

    var menuAccessibilityLabel: String {
        if let errorMessage { return "LidAwake needs attention: \(errorMessage)" }
        if isStopping { return "LidAwake is restoring normal sleep" }
        if externalSession {
            if externalLease?.stopping == true {
                return "LidAwake: a previous session is restoring sleep"
            }
            return "LidAwake: another session is active"
        }
        if !watchdogHealthy { return "LidAwake: the safety check needs repair" }
        if isActive {
            let modeText = activeSession?.mode == .system
                ? "all sleep blocked"
                : "lid-close sleep blocked"
            if externalSleepDisabled {
                return "LidAwake on, \(modeText); sleep is also off outside LidAwake"
            }
            return "LidAwake on, \(modeText)"
        }
        if externalSleepDisabled { return "LidAwake off: sleep is already off" }
        return "LidAwake off, normal sleep"
    }

    /// True when the system-wide sleep flag is set by something other than the
    /// current local or visible external session.
    var externalSleepDisabled: Bool {
        guard snapshot.sleepDisabledKnown, snapshot.sleepDisabled else { return false }
        if let session = activeSession, session.mode == .system { return false }
        if let lease = externalLease, lease.mode == .system, lease.ownsPmset { return false }
        return true
    }

    var presentation: SessionPresentation {
        SessionPresentationBuilder.make(
            SessionPresentationInput(
                isActive: isActive,
                isStopping: controller.stopping,
                externalSession: externalSession,
                externalSessionStopping: externalLease?.stopping ?? false,
                externalSleepDisabled: externalSleepDisabled,
                errorMessage: errorMessage,
                mode: activeSession?.mode ?? externalLease?.mode ?? mode,
                tripMode: activeSession?.config.tripMode ?? externalLease?.tripMode ?? tripMode,
                hasSeenLidClosed: activeSession?.hasSeenLidClosed ?? false,
                lidClosed: snapshot.lidClosed,
                sleepStateKnown: snapshot.sleepDisabledKnown,
                clamshellCausesSleepKnown: snapshot.clamshellCausesSleepKnown,
                clamshellCausesSleep: snapshot.clamshellCausesSleep,
                onAC: snapshot.onAC,
                charging: snapshot.charging,
                batteryPercent: snapshot.batteryPercent,
                batteryInfoKnown: snapshot.batteryInfoKnown,
                batteryFloor: activeSession?.config.batteryFloor ?? externalLease?.batteryFloor ?? batteryFloor,
                thermalGuard: activeSession?.config.thermalGuard ?? externalLease?.thermalGuard ?? thermalGuard,
                thermalState: snapshot.thermalState,
                watchdogHealthy: watchdogHealthy,
                watchdogLoaded: watchdogLoaded,
                lastEvent: lastEvent
            )
        )
    }

    /// Remaining wall-clock time without the "left" suffix; the view adds the
    /// appropriate sentence. Passing a date lets TimelineView update once a second
    /// without republishing the whole model.
    func timeRemainingText(at date: Date = Date()) -> String? {
        if controller.stopping { return nil }
        guard let deadline = activeSession?.deadline else { return nil }
        let remaining = Int(deadline.timeIntervalSince(date).rounded())
        guard remaining > 0 else { return "0:00" }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    func sessionProgress(at date: Date = Date()) -> Double? {
        guard let session = activeSession, let deadline = session.deadline else { return nil }
        let total = deadline.timeIntervalSince(session.startedAt)
        guard total > 0 else { return nil }
        let elapsed = date.timeIntervalSince(session.startedAt)
        return min(max(elapsed / total, 0), 1)
    }

    var fallbackInstalled: Bool {
        pmset.isGrantInstalled
    }

    func dismissError() {
        errorMessage = nil
        refresh()
    }

    func revealFallbackInstaller() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("install-pmset-fallback.sh"),
              FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "The setup script is missing from the app bundle."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    var diagnostics: String {
        diagnosticsText()
    }

    private func tick() {
        guard !isDisarming else { return }
        if controller.active != nil {
            // Ownership first: a stale local controller must never disarm a
            // session that another process has taken over.
            reconcileOwnership()
            if controller.active == nil {
                refresh()
                return
            }
            if let deadline = controller.active?.deadline, Date() >= deadline {
                attemptDisarm(.timer)
                return
            }
            if controller.stopping {
                if !watchdogInstaller.isHeartbeatFresh() {
                    attemptDisarm(.watchdog)
                }
                refresh()
                return
            }
            if let reason = controller.tick() {
                attemptDisarm(reason)
                return
            }
            // The heartbeat file is the liveness signal. Do not let a
            // transient `launchctl` probe end a healthy session.
            let watchdogFresh = watchdogInstaller.isHeartbeatFresh()
            if !watchdogFresh {
                if let grace = wakeGraceUntil, Date() < grace {
                    refresh()
                    return
                }
                watchdogMissCount += 1
                if watchdogMissCount >= 2 {
                    // Do not overwrite a restore failure with a generic
                    // "restoring" message. disarm() owns the error state.
                    attemptDisarm(.watchdog)
                    return
                }
            } else {
                watchdogMissCount = 0
                wakeGraceUntil = nil
            }
        }
        refresh()
    }

    private func renew() {
        if controller.active != nil {
            controller.renewLease()
        }
        let loaded = watchdogInstaller.isLoaded
        if loaded != watchdogLoaded { watchdogLoaded = loaded }
        let healthy = loaded && watchdogInstaller.isHeartbeatFresh()
        if healthy != watchdogHealthy { watchdogHealthy = healthy }
        refresh()
    }

    private func refresh() {
        let newSnapshot = monitor.snapshot()
        if newSnapshot != snapshot { snapshot = newSnapshot }

        let newActive = controller.active != nil
        if newActive != isActive { isActive = newActive }

        let newSession = controller.active
        if newSession != activeSession { activeSession = newSession }

        // Do not spawn `launchctl` here: refresh runs every second. The loaded
        // state is re-read by renew() every five seconds and after a repair.
        let healthy = watchdogLoaded && watchdogInstaller.isHeartbeatFresh()
        if healthy != watchdogHealthy { watchdogHealthy = healthy }

        let lease = try? store.load()
        var newExternal = false
        if controller.active == nil, let lease, lease.bootID == SystemInfo.bootID {
            let live = lease.pid != SystemInfo.processID &&
                SystemInfo.processIsAlive(lease.pid)
            // A stopping lease is recovery work even if the owning process is
            // gone. A dead, non-stopping lease is stale and may be replaced.
            newExternal = live || lease.stopping
        }
        if newExternal != externalSession { externalSession = newExternal }
        if newExternal {
            if externalLease != lease { externalLease = lease }
        } else if externalLease != nil {
            externalLease = nil
        }

        syncMenuIcon()
    }

    private func reconcileOwnership() {
        guard controller.active != nil else { return }
        let lease = try? store.load()
        guard let lease else {
            // The controller may still hold the kernel flag; let disarm() own
            // the outcome and error message.
            attemptDisarm(.error)
            return
        }
        if lease.pid != SystemInfo.processID || lease.bootID != SystemInfo.bootID {
            controller.abandonLocalSession()
            caffeinate.stop()
            errorMessage = "Another LidAwake process took ownership of the session."
        }
    }

    private func syncMenuIcon() {
        menuIconModel.update(
            symbol: menuIcon,
            accessibilityLabel: menuAccessibilityLabel
        )
    }

    private func attemptDisarm(_ reason: DisarmReason) {
        if let last = lastDisarmAttempt, Date().timeIntervalSince(last) < 5 {
            return
        }
        lastDisarmAttempt = Date()
        disarm(reason: reason)
        if controller.active != nil {
            lastDisarmAttempt = Date()
        }
    }

    private func ensureWatchdog(force: Bool = false) {
        guard let helper = Bundle.main.resourceURL?.appendingPathComponent("lidawake-ctl") else {
            errorMessage = "Watchdog helper is missing from the app bundle."
            return
        }
        guard FileManager.default.fileExists(atPath: helper.path) else {
            errorMessage = "Watchdog helper is missing from the app bundle."
            return
        }
        if !force && watchdogInstaller.isLoaded {
            return
        }
        do {
            try watchdogInstaller.install(helperSource: helper)
        } catch {
            errorMessage = "Could not install the safety watchdog: \(error.localizedDescription)"
        }
    }

    private func recoverStaleSessionAtLaunch() {
        let runner = WatchdogRunner(leaseStore: store, system: monitor)
        let action = runner.runOnce()
        switch action {
        case .recovered(let reason):
            notifications.notify(title: "Recovered a stale session", body: reason)
        case .clearFailed(let reason):
            errorMessage = "Could not clear a stale session: \(reason). Check the watchdog and permissions."
        case .healthy:
            break
        }
        // A live lease from another running instance is left alone. This app
        // is single-instance (LSMultipleInstancesProhibited), so a remaining
        // lease normally means recovery could not complete; the watchdog will
        // keep retrying and the UI will show the external state.
    }

    private func clearError() {
        errorMessage = nil
    }

    private func armMessage(config: SessionConfig) -> String {
        let modeText = config.mode == .clamshell
            ? "Armed. Close the lid when you are ready."
            : "All sleep is disabled."
        let effective = min(config.duration ?? config.maxDuration, config.maxDuration)
        let minutes = max(1, Int(effective / 60))
        return "\(modeText) Battery limit \(config.batteryFloor)%. Turns off in \(minutes) min (8-hour maximum)."
    }

    private func diagnosticsText() -> String {
        let lease = try? store.load()
        let health = try? store.loadHealth()
        let snapshot = monitor.snapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        struct Diagnostics: Codable {
            var generatedAt: Date
            var version: String
            var bootID: String
            var pid: Int32
            var isActive: Bool
            var isStopping: Bool
            var externalSession: Bool
            var externalLease: SessionLease?
            var lastEvent: DisarmEvent?
            var errorMessage: String?
            var isBusy: Bool
            var launchAtLogin: Bool
            var mode: String
            var timerPreset: String
            var tripMode: Bool
            var batteryFloor: Int
            var thermalGuard: Bool
            var activeSession: ActiveSessionDTO?
            var snapshot: SnapshotDTO
            var lease: SessionLease?
            var watchdogHealth: WatchdogHealth?
            var watchdogLoaded: Bool
            var watchdogHealthy: Bool
            var supportDirectory: String
        }
        struct ActiveSessionDTO: Codable {
            var mode: String
            var startedAt: Date
            var deadline: Date?
            var duration: TimeInterval?
            var batteryFloor: Int
            var tripMode: Bool
            var thermalGuard: Bool
            var hasSeenLidClosed: Bool
        }
        struct SnapshotDTO: Codable {
            var sleepDisabled: Bool
            var sleepDisabledKnown: Bool
            var lidClosed: Bool
            var clamshellCausesSleep: Bool
            var clamshellCausesSleepKnown: Bool
            var onAC: Bool
            var batteryPercent: Int?
            var batteryInfoKnown: Bool
            var charging: Bool
            var thermalState: Int
            var lowPowerMode: Bool
        }

        let dto = SnapshotDTO(
            sleepDisabled: snapshot.sleepDisabled,
            sleepDisabledKnown: snapshot.sleepDisabledKnown,
            lidClosed: snapshot.lidClosed,
            clamshellCausesSleep: snapshot.clamshellCausesSleep,
            clamshellCausesSleepKnown: snapshot.clamshellCausesSleepKnown,
            onAC: snapshot.onAC,
            batteryPercent: snapshot.batteryPercent,
            batteryInfoKnown: snapshot.batteryInfoKnown,
            charging: snapshot.charging,
            thermalState: snapshot.thermalState.rawValue,
            lowPowerMode: snapshot.lowPowerMode
        )
        let active = activeSession.map {
            ActiveSessionDTO(
                mode: $0.mode.rawValue,
                startedAt: $0.startedAt,
                deadline: $0.deadline,
                duration: $0.config.duration,
                batteryFloor: $0.config.batteryFloor,
                tripMode: $0.config.tripMode,
                thermalGuard: $0.config.thermalGuard,
                hasSeenLidClosed: $0.hasSeenLidClosed
            )
        }
        let diagnostics = Diagnostics(
            generatedAt: Date(),
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            bootID: SystemInfo.bootID,
            pid: SystemInfo.processID,
            isActive: isActive,
            isStopping: controller.stopping,
            externalSession: externalSession,
            externalLease: externalLease,
            lastEvent: lastEvent,
            errorMessage: errorMessage,
            isBusy: isBusy,
            launchAtLogin: launchAtLogin,
            mode: mode.rawValue,
            timerPreset: timerPreset.rawValue,
            tripMode: tripMode,
            batteryFloor: batteryFloor,
            thermalGuard: thermalGuard,
            activeSession: active,
            snapshot: dto,
            lease: lease,
            watchdogHealth: health,
            watchdogLoaded: watchdogLoaded,
            watchdogHealthy: watchdogHealthy,
            supportDirectory: store.directory.path
        )
        guard let data = try? encoder.encode(diagnostics),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
