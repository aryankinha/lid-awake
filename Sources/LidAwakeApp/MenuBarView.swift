import SwiftUI
import AppKit
import LidAwakeCore

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    var onSizeChange: ((CGFloat) -> Void)? = nil
    private var onOpenDiagnostics: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var showAdvanced: Bool
    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 49
    @State private var footerHeight: CGFloat = 42
    @State private var screenHeight: CGFloat = 900

    private let sideInset: CGFloat = 16

    init(
        model: AppModel,
        onSizeChange: ((CGFloat) -> Void)? = nil,
        showAdvanced: Bool = false,
        onOpenDiagnostics: (() -> Void)? = nil
    ) {
        self.model = model
        self.onSizeChange = onSizeChange
        self.onOpenDiagnostics = onOpenDiagnostics
        _showAdvanced = State(initialValue: showAdvanced)
    }

    private var scrollLimit: CGFloat {
        // Budget for the popover chrome and keep the header and footer visible.
        max(80, screenHeight - headerHeight - footerHeight - 40)
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
            .frame(height: min(contentHeight > 0 ? contentHeight : 420, scrollLimit))
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
        VStack(alignment: .leading, spacing: 10) {
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
        HStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 23, height: 23)
                .accessibilityHidden(true)

            Text("LidAwake")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .foregroundStyle(.primary)

            Spacer()
        }
    }

    // MARK: - Primary control

    private var primaryModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: model.menuIcon.image)
                    .foregroundStyle(model.isActive ? Theme.activeText : Theme.secondaryText)
                    .frame(width: 24, height: 22)
                    .accessibilityHidden(true)

                Text("Keep this Mac awake")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Toggle("", isOn: activeBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(
                        model.externalSession ||
                        model.isStopping ||
                        model.isBusy ||
                        model.isArmBlocked
                    )
                    .accessibilityLabel("Keep this Mac awake")
                    .accessibilityValue(model.isActive ? "On" : "Off")
                    .accessibilityHint(primaryAccessibilityHint)
            }

            VStack(alignment: .leading, spacing: 5) {
                statusLine

                Text(model.presentation.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let risk = model.presentation.riskNote {
                    Label(risk, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.warningText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.externalSleepDisabled && !model.externalSession {
                    externalSleepControl
                }

                if let note = model.presentation.eventNote {
                    Label(note, systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 34)

            if model.isActive {
                activeSessionLine
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(primaryBackground)
    }

    @ViewBuilder
    private var externalSleepControl: some View {
        if model.isActive {
            Text("Sleep was disabled outside LidAwake. Turning off won't restore normal sleep until it's cleared.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.warningText)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.isBusy {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Clearing the sleep flag")
        } else {
            Button("Clear…") {
                model.clearExternalSleepFlag()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Clears the sleep setting that was changed outside LidAwake.")
        }
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(model.presentation.stateLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(stateColor)
            }
            Text(model.presentation.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusTextColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activeSessionLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if model.isStopping {
                        Text("Restoring normal sleep…")
                    } else if let remaining = model.timeRemainingText(at: context.date) {
                        Text("Turns off in \(remaining)\(tripModeSuffix)")
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Session active")
                    }
                    Spacer(minLength: 4)
                    Text(model.presentation.modeShort)
                        .foregroundStyle(Theme.secondaryText)
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(model.isStopping ? Theme.warningText : Theme.activeText)

                if let progress = model.sessionProgress(at: context.date) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(model.isStopping ? Theme.warning : Theme.activeTrack)
                        .animation(
                            reduceMotion ? nil : .linear(duration: 1),
                            value: progress
                        )
                }
            }
        }
    }

    private var tripModeSuffix: String {
        guard let session = model.activeSession else { return "" }
        guard session.config.tripMode, session.hasSeenLidClosed else { return "" }
        return " or when you reopen the lid"
    }

    private var primaryBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.primaryRadius, style: .continuous)
                .fill(Theme.primaryFill)
            RoundedRectangle(cornerRadius: Theme.primaryRadius, style: .continuous)
                .fill(Theme.active.opacity(model.isActive ? (colorScheme == .dark ? 0.09 : 0.07) : 0))
        }
    }

    private var stateColor: Color {
        if model.isStopping || model.externalSession { return Theme.warningText }
        if model.isActive { return Theme.activeText }
        return Theme.secondaryText
    }

    private var statusTextColor: Color {
        model.isArmBlocked || model.isStopping || model.presentation.isWarning
            ? Theme.warningText : Theme.secondaryText
    }

    private var dotColor: Color {
        model.menuIcon == .attention ? Theme.warningText : stateColor
    }

    private var primaryAccessibilityHint: String {
        if model.externalSession {
            if model.externalLease?.stopping == true {
                return "A previous session is restoring sleep. Wait for the safety check to finish."
            }
            return "Another LidAwake session is active. Turn it off there first."
        }
        if model.isStopping { return "The safety check is restoring normal sleep." }
        if !model.watchdogHealthy {
            return "The safety check needs repair before LidAwake can start."
        }
        if model.externalSleepDisabled {
            return "Sleep is already off outside LidAwake. Clear it before starting."
        }
        if !model.snapshot.batteryInfoKnown ||
            (!model.snapshot.onAC && model.snapshot.batteryPercent == nil) {
            return "The battery can't be read. LidAwake won't start without a battery reading."
        }
        if effectiveMode == .system && !model.fallbackInstalled {
            return "All sleep mode needs a one-time setup."
        }
        if effectiveMode == .system && !model.snapshot.sleepDisabledKnown {
            return "Sleep state is unavailable, so All sleep mode can't be verified."
        }
        if model.isArmBlocked { return model.presentation.subtitle }
        if model.isActive {
            if let remaining = model.timeRemainingText() {
                return "Turns off in \(remaining)\(tripModeSuffix)."
            }
            return "Lid-close sleep is blocked."
        }
        return model.presentation.subtitle
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { model.isActive },
            set: { model.setActive($0) }
        )
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
                    ? "LidAwake is still trying to restore sleep. Keep it running."
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
                message: "LidAwake can't turn on until the background check is running.",
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
                message: "macOS still sleeps this Mac when the lid closes. Keep the lid open, or turn LidAwake off and choose All sleep.",
                actionTitle: "Diagnostics…",
                action: openDiagnostics,
                canDismiss: false
            )
        }

        if effectiveMode == .system, !model.fallbackInstalled, !model.isActive, !model.externalSession {
            return NoticeSpec(
                tone: .warning,
                title: "All sleep needs a one-time setup",
                message: "An administrator must approve it before LidAwake can use this mode.",
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
                duration: active.config.duration,
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

    @ViewBuilder
    private var settingsArea: some View {
        if model.isActive {
            sessionSummary(
                title: "This session",
                trailing: "Turn LidAwake off to change",
                duration: effectiveDuration,
                trip: effectiveTrip,
                floor: effectiveFloor,
                thermal: effectiveThermal
            )
        } else if model.externalSession {
            if model.externalLease != nil {
                let recovering = model.externalLease?.stopping == true
                sessionSummary(
                    title: recovering ? "Session recovery" : "Another session",
                    trailing: recovering ? "Waiting for safety check" : "Managed elsewhere",
                    duration: effectiveDuration,
                    trip: effectiveTrip,
                    floor: effectiveFloor,
                    thermal: effectiveThermal
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(title: "Session recovery", trailing: "Waiting for safety check")
                    SettingsGroup {
                        SettingsValueRow(
                            title: "Session details",
                            value: "Unavailable"
                        )
                        GroupDivider()
                        SystemStatusLine(presentation: model.presentation)
                    }
                }
            }
        } else {
            editableSettings
        }
    }

    private var editableSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Session settings")
            editableSettingsGroup
        }
    }

    private var editableSettingsGroup: some View {
        SettingsGroup {
            SettingsMenuRow(
                title: "Turn off after",
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
                title: "Stop at battery",
                value: "\(model.batteryFloor)%",
                choices: batteryChoices,
                selectedID: "\(model.batteryFloor)",
                onSelect: { choice in
                    guard let value = Int(choice.id) else { return }
                    model.batteryFloor = min(max(value, 10), 50)
                }
            )
            GroupDivider()
            SettingsToggleRow(
                title: "Stop if the Mac runs hot",
                isOn: $model.thermalGuard
            )
            GroupDivider()
            SettingsToggleRow(
                title: "Turn off when I reopen the lid",
                subtitle: "After it has been closed once.",
                isOn: $model.tripMode
            )
            GroupDivider()
            SystemStatusLine(presentation: model.presentation)
        }
    }

    private func sessionSummary(
        title: String,
        trailing: String,
        duration: TimeInterval?,
        trip: Bool,
        floor: Int,
        thermal: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: title, trailing: trailing)
            SettingsGroup {
                SettingsValueRow(
                    title: "Turn off after",
                    value: TimerChoice.displayDuration(duration)
                )
                GroupDivider()
                SettingsValueRow(title: "Stop at battery", value: "\(floor)%")
                GroupDivider()
                SettingsValueRow(
                    title: "Stop if the Mac runs hot",
                    value: thermal ? "On" : "Off"
                )
                GroupDivider()
                SettingsValueRow(
                    title: "Turn off when I reopen the lid",
                    value: trip ? "On" : "Off"
                )
                GroupDivider()
                SystemStatusLine(presentation: model.presentation)
            }
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
            Button {
                showAdvanced.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Label("Advanced", systemImage: "gearshape")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced")
            .accessibilityValue(showAdvanced ? "Expanded" : "Collapsed")
            .accessibilityHint(showAdvanced ? "Hide additional settings." : "Show additional settings.")

            if showAdvanced {
                GroupDivider()
                advancedContent
                    .padding(.bottom, 4)
            }
        }
        .background(Theme.groupFill, in: RoundedRectangle(cornerRadius: Theme.groupRadius))
    }

    private var advancedContent: some View {
        VStack(spacing: 0) {
            if model.isActive || model.externalSession {
                SettingsValueRow(
                    title: "Sleep control",
                    value: effectiveMode.friendlyName
                )
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
                Text(effectiveMode.friendlyDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warningText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
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
                    Label("Diagnostics…", systemImage: "stethoscope")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
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
            HStack(spacing: 10) {
                if model.isActive {
                    Text("Keep the Mac on a hard, ventilated surface.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
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
            Label("Quit", systemImage: "power")
        }
        .disabled(model.isBusy)
        .accessibilityLabel("Quit LidAwake")
        .help("Quit LidAwake and restore normal sleep for this session.")

        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}
