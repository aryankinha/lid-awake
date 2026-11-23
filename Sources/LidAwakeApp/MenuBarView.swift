import SwiftUI
import AppKit
import LidAwakeCore

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    private let onSizeChange: ((CGFloat) -> Void)?
    private let onOpenDiagnostics: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showAdvanced: Bool
    @State private var contentHeight = PopoverLayout.compactScrollHeight
    @State private var advancedDetailsHeight: CGFloat = 0
    @State private var headerHeight = PopoverLayout.headerHeight
    @State private var footerHeight = PopoverLayout.footerHeight
    @State private var screenHeight: CGFloat

    private let sideInset: CGFloat = 16

    init(
        model: AppModel,
        onSizeChange: ((CGFloat) -> Void)? = nil,
        showAdvanced: Bool = false,
        onOpenDiagnostics: (() -> Void)? = nil,
        initialScreenHeight: CGFloat? = nil
    ) {
        self.model = model
        self.onSizeChange = onSizeChange
        self.onOpenDiagnostics = onOpenDiagnostics
        _showAdvanced = State(initialValue: showAdvanced)
        _screenHeight = State(
            initialValue: initialScreenHeight
                ?? NSScreen.main?.visibleFrame.height
                ?? 900
        )
    }

    private var scrollLimit: CGFloat {
        PopoverLayout.scrollLimit(
            screenHeight: screenHeight, headerHeight: headerHeight, footerHeight: footerHeight
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, sideInset)
                .padding(.vertical, 12)
                .reportHeight { headerHeight = $0 }

            ScrollView {
                panelContent
                    .reportHeight { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, scrollLimit))
            .modifier(PanelScrollBehavior())

            footer
                .reportHeight { footerHeight = $0 }
        }
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            PanelScreenReader { screenHeight = $0 }
        }
        .reportHeight { onSizeChange?($0) }
        .onAppear {
            if onSizeChange == nil { model.refreshLaunchAtLogin() }
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            primaryModule
            if let notice = noticeSpec {
                NoticeBanner(
                    tone: notice.tone,
                    title: notice.title,
                    message: notice.message,
                    actionTitle: notice.actionTitle,
                    action: notice.action,
                    actionDisabled: notice.actionDisabled && model.isBusy,
                    dismiss: notice.canDismiss ? { model.dismissError() } : nil
                )
            }
            settingsArea
            advancedSection
        }
        .padding(.horizontal, sideInset)
        .padding(.bottom, 12)
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Text("LidAwake")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .foregroundStyle(.primary)

            Spacer()
        }
    }

    // MARK: - Primary control

    private var wakeState: WakeControlState {
        WakeControlState(
            isActive: model.isActive,
            isRestoring: model.isStopping || model.externalLease?.stopping == true,
            isExternal: model.externalSession,
            isBusy: model.isBusy,
            isArmBlocked: model.isArmBlocked
        )
    }

    private var primaryModule: some View {
        let state = wakeState
        let presentation = model.presentation
        let sessionState = state == .busy && model.isActive ? .on : state

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                wakeIcon(sessionState)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keep Mac awake")
                        .font(.system(size: 17, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)

                    Text(model.externalSleepDisabled && !model.isActive && !model.externalSession
                        ? "Sleep disabled externally"
                        : presentation.statusText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            wakeButton(state)

            Divider()
            statusMetrics(sessionState)

            if let risk = presentation.riskNote {
                WarningLine(text: risk)
            }
            if model.externalSleepDisabled && !model.externalSession {
                externalSleepControl
            }
            if state == .blocked, model.watchdogHealthy, !model.externalSleepDisabled,
               effectiveMode != .system || model.fallbackInstalled {
                Text(presentation.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sessionState == .on, model.snapshot.lidClosed, !presentation.isClamshellWarning {
                Text("Keep the Mac ventilated.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if presentation.eventNote != nil, let event = model.lastEvent {
                Label(event.reason.displayName, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Last session: \(event.reason.displayName)")
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: Theme.primaryRadius)
                .fill(Theme.primaryFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.primaryRadius)
                .strokeBorder(
                    sessionState == .on ? Theme.success.opacity(0.42) : Theme.hairline,
                    lineWidth: 1
                )
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: sessionState == .on)
                .allowsHitTesting(false)
        }
    }

    private func wakeIcon(_ state: WakeControlState) -> some View {
        let symbol: String
        let tint: Color
        switch model.menuIcon {
        case .idle:
            symbol = "laptopcomputer"
            tint = Theme.textSecondary
        case .active:
            symbol = "bolt.circle"
            tint = Theme.success
        case .attention:
            symbol = "exclamationmark.triangle"
            tint = model.errorMessage == nil ? Theme.warning : Theme.danger
        }

        return Image(systemName: symbol)
            .font(.system(size: 19, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .scaleEffect(state == .on ? 1.14 : 1)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: state == .on)
            .accessibilityHidden(true)
    }

    private func wakeButton(_ state: WakeControlState) -> some View {
        Button {
            if let target = state.requestedActive {
                model.setActive(target)
            }
        } label: {
            Label(state.actionTitle, systemImage: state == .on ? "power" : "bolt")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(state == .on ? Color(nsColor: .secondaryLabelColor) : Theme.accent)
        .controlSize(.large)
        .disabled(state.requestedActive == nil)
        .accessibilityLabel(state.actionTitle)
        .accessibilityHint(wakeActionHint(state))
    }

    private func wakeActionHint(_ state: WakeControlState) -> String {
        switch state {
        case .off:
            return "Starts a LidAwake session."
        case .on:
            return model.externalSleepDisabled
                ? "Ends the session. Sleep is also disabled outside LidAwake."
                : "Ends the session and restores normal sleep."
        case .busy, .blocked, .restoring, .external:
            return model.presentation.subtitle
        }
    }

    private func statusMetrics(_ state: WakeControlState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                SessionMetric(
                    title: state == .on ? "Time left" : "Session",
                    value: state.sessionValue(remaining: model.timeRemainingText(at: context.date))
                )
            }
            metricDivider
            SessionMetric(title: "Battery", value: batteryValue)
            metricDivider
            SessionMetric(title: "Lid", value: lidValue)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 32)
            .accessibilityHidden(true)
    }

    private var lidValue: String {
        guard model.snapshot.lidStateKnown else { return "Unknown" }
        return model.snapshot.lidClosed ? "Closed" : "Open"
    }

    private var batteryValue: String {
        let snapshot = model.snapshot
        guard snapshot.batteryInfoKnown else { return "Unknown" }
        if let percentage = snapshot.batteryPercent { return "\(percentage)%" }
        return snapshot.onAC ? "AC power" : "Unknown"
    }

    @ViewBuilder
    private var externalSleepControl: some View {
        if model.isActive {
            WarningLine(text: "Sleep is also disabled outside LidAwake.")
        } else if model.isBusy {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Clearing the sleep flag")
        } else {
            Button("Restore Sleep…") {
                model.clearExternalSleepFlag()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Clears the sleep setting changed outside LidAwake.")
        }
    }

    // MARK: - Notices

    private struct NoticeSpec {
        let tone: NoticeBanner.Tone
        let title: String
        let message: String
        var actionTitle: String?
        var action: (() -> Void)?
        var actionDisabled = false
        var canDismiss = false
    }

    private var noticeSpec: NoticeSpec? {
        if let error = model.errorMessage,
           model.isStopping || !model.watchdogHealthy {
            return NoticeSpec(
                tone: .danger,
                title: model.isStopping ? "Couldn't restore normal sleep" : "Safety check needs repair",
                message: model.isStopping
                    ? "Keep LidAwake running while it restores sleep."
                    : error,
                actionTitle: model.isStopping ? "Try Again" : "Repair",
                action: {
                    if model.isStopping {
                        model.setActive(false)
                    } else {
                        model.repairWatchdog()
                    }
                },
                actionDisabled: true,
                canDismiss: false
            )
        }

        if !model.watchdogHealthy {
            return NoticeSpec(
                tone: .warning,
                title: "Safety check needs repair",
                message: "Repair the background check to start a session.",
                actionTitle: "Repair",
                action: { model.repairWatchdog() },
                actionDisabled: true,
                canDismiss: false
            )
        }

        if model.presentation.isClamshellWarning {
            return NoticeSpec(
                tone: .warning,
                title: "Lid-close sleep isn't blocked",
                message: "Keep the lid open or end the session and choose All sleep.",
                actionTitle: "Diagnostics…",
                action: openDiagnostics,
                canDismiss: false
            )
        }

        if effectiveMode == .system, !model.fallbackInstalled, !model.isActive, !model.externalSession {
            return NoticeSpec(
                tone: .warning,
                title: "All sleep needs a one-time setup",
                message: "Administrator approval is required.",
                actionTitle: "Set Up…",
                action: { model.revealFallbackInstaller() },
                canDismiss: false
            )
        }

        if let error = model.errorMessage {
            return NoticeSpec(
                tone: .warning,
                title: "Couldn't finish that",
                message: error,
                actionTitle: model.isArmBlocked || model.isActive ? nil : "Try Again",
                action: model.isArmBlocked || model.isActive ? nil : { model.arm() },
                actionDisabled: true,
                canDismiss: true
            )
        }

        return nil
    }

    // MARK: - Settings

    /// One source of truth for the values shown in the active/external summary
    /// and the read-only Advanced row. Never mix saved defaults into a running
    /// session's presentation.
    private struct SessionDetails {
        let mode: SleepMode
        let duration: TimeInterval?
        let trip: Bool
        let floor: Int
        let thermal: Bool
    }

    private var sessionDetails: SessionDetails {
        if let active = model.activeSession {
            return SessionDetails(
                mode: active.mode,
                duration: active.deadline.map { $0.timeIntervalSince(active.startedAt) },
                trip: active.config.tripMode,
                floor: active.config.batteryFloor,
                thermal: active.config.thermalGuard
            )
        }
        if let lease = model.externalLease {
            return SessionDetails(
                mode: lease.mode,
                duration: lease.deadline.map { $0.timeIntervalSince(lease.startedAt) },
                trip: lease.tripMode,
                floor: lease.batteryFloor,
                thermal: lease.thermalGuard
            )
        }
        return SessionDetails(
            mode: model.mode,
            duration: model.timerPreset.seconds,
            trip: model.tripMode,
            floor: model.batteryFloor,
            thermal: model.thermalGuard
        )
    }

    private var effectiveMode: SleepMode { sessionDetails.mode }
    private var effectiveDuration: TimeInterval? { sessionDetails.duration }
    private var effectiveTrip: Bool { sessionDetails.trip }
    private var effectiveFloor: Int { sessionDetails.floor }
    private var effectiveThermal: Bool { sessionDetails.thermal }

    private var sessionSettingsLocked: Bool {
        model.isActive || model.externalSession
    }

    private var settingsArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Session Controls")
                .accessibilityAddTraits(.isHeader)

            SettingsGroup {
                if model.externalSession && model.externalLease == nil {
                    SettingsValueRow(title: "Session controls", value: "Unavailable")
                } else if sessionSettingsLocked {
                    SettingsValueRow(title: "Auto-stop timer", value: TimerChoice.displayDuration(effectiveDuration))
                    GroupDivider()
                    SettingsValueRow(title: "Battery limit", value: "\(effectiveFloor)%")
                    GroupDivider()
                    lidReopenSetting
                } else {
                    SettingsMenuRow(
                        title: "Auto-stop timer",
                        value: TimerChoice(preset: model.timerPreset).title,
                        choices: TimerChoice.allCases.map {
                            SettingsMenuChoice(id: $0.id, title: $0.title)
                        },
                        selectedID: TimerChoice(preset: model.timerPreset).id,
                        onSelect: { choice in
                            guard let timer = TimerChoice(rawValue: choice.id) else { return }
                            model.timerPreset = timer.preset
                        }
                    )
                    GroupDivider()
                    SettingsMenuRow(
                        title: "Battery limit",
                        value: "\(model.batteryFloor)%",
                        choices: batteryChoices,
                        selectedID: "\(model.batteryFloor)",
                        onSelect: { choice in
                            guard let value = Int(choice.id) else { return }
                            model.batteryFloor = min(max(value, 10), 50)
                        }
                    )
                    GroupDivider()
                    lidReopenSetting
                }
            }
        }
    }

    @ViewBuilder
    private var lidReopenSetting: some View {
        let title = "Stop when lid opens"
        let subtitle = "Automatically disable LidAwake when the MacBook lid is reopened after being closed."
        if sessionSettingsLocked {
            SettingsValueRow(title: title, value: effectiveTrip ? "On" : "Off", subtitle: subtitle)
        } else {
            SettingsToggleRow(title: title, isOn: $model.tripMode, subtitle: subtitle)
        }
    }

    @ViewBuilder
    private var temperatureSetting: some View {
        let title = "Temperature Protection"
        let subtitle = "Automatically stop the awake session if the Mac gets too hot."
        if sessionSettingsLocked {
            SettingsValueRow(title: title, value: effectiveThermal ? "On" : "Off", subtitle: subtitle)
        } else {
            SettingsToggleRow(title: title, isOn: $model.thermalGuard, subtitle: subtitle)
        }
    }

    private var batteryChoices: [SettingsMenuChoice] {
        var values = Set(stride(from: 10, through: 50, by: 5))
        values.insert(min(max(model.batteryFloor, 10), 50))
        return values.sorted().map {
            SettingsMenuChoice(id: "\($0)", title: "\($0)%")
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(spacing: 0) {
            Button(action: toggleAdvanced) {
                HStack(spacing: 8) {
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Label("Advanced Settings", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced Settings")
            .accessibilityValue(showAdvanced ? "Expanded" : "Collapsed")
            .accessibilityHint(showAdvanced ? "Hide additional settings." : "Show additional settings.")

            VStack(spacing: 0) {
                GroupDivider()
                advancedContent
                    .padding(.bottom, 4)
            }
            .fixedSize(horizontal: false, vertical: true)
            .reportHeight { advancedDetailsHeight = $0 }
            .frame(height: showAdvanced ? nil : 0, alignment: .top)
            .clipped()
            .disabled(!showAdvanced)
            .allowsHitTesting(showAdvanced)
            .accessibilityHidden(!showAdvanced)
        }
        .background(
            Theme.groupFill,
            in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
        )
    }

    private func toggleAdvanced() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            showAdvanced.toggle()
            guard advancedDetailsHeight > 0 else { return }
            // Measure the disclosure independently so the scroll view and
            // native popover resize in the same update as the row changes.
            contentHeight += showAdvanced ? advancedDetailsHeight : -advancedDetailsHeight
            onSizeChange?(headerHeight + min(contentHeight, scrollLimit) + footerHeight)
        }
    }

    private var advancedContent: some View {
        VStack(spacing: 0) {
            if model.externalSession && model.externalLease == nil {
                SettingsValueRow(title: "Sleep control", value: "Unavailable")
            } else if sessionSettingsLocked {
                SettingsValueRow(title: "Sleep control", value: effectiveMode.friendlyName)
            } else {
                SettingsMenuRow(
                    title: "Sleep control",
                    value: effectiveMode.friendlyName,
                    choices: SleepMode.allCases.map {
                        SettingsMenuChoice(id: $0.rawValue, title: $0.friendlyName)
                    },
                    selectedID: effectiveMode.rawValue,
                    onSelect: { choice in
                        guard let mode = SleepMode(rawValue: choice.id) else { return }
                        model.mode = mode
                    }
                )
            }

            if effectiveMode == .system {
                WarningLine(text: effectiveMode.friendlyDetail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if !model.externalSession || model.externalLease != nil {
                GroupDivider()
                temperatureSetting
            }

            GroupDivider()

            SettingsToggleRow(
                title: "Open at Login",
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ),
                disabled: model.isBusy
            )

            GroupDivider()

            Button(action: openDiagnostics) {
                HStack {
                    Label("Diagnostics…", systemImage: "waveform.path.ecg")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Diagnostics")
        }
    }

    private func openDiagnostics() {
        onOpenDiagnostics?()
        DiagnosticsWindowController.shared.show(model: model)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                quitButton
            }
            .padding(.horizontal, sideInset)
            .padding(.vertical, 9)
        }
    }

    private var quitButton: some View {
        Button {
            model.quit()
        } label: {
            Label("Quit", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .disabled(model.isBusy)
        .accessibilityLabel("Quit LidAwake")
        .help("Quit LidAwake and restore normal sleep for this session.")

        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}
