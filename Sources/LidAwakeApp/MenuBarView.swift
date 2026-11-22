import SwiftUI
import AppKit
import LidAwakeCore

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    var onSizeChange: ((CGFloat) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var showAdvanced: Bool
    @State private var advancedHovered = false
    @State private var diagnosticsHovered = false
    @State private var quitHovered = false
    @State private var scrollContentHeight: CGFloat = 490
    @FocusState private var advancedFocused: Bool
    @FocusState private var diagnosticsFocused: Bool
    @FocusState private var quitFocused: Bool
    @FocusState private var clearFocused: Bool

    private let sideInset: CGFloat = 16

    init(
        model: AppModel,
        onSizeChange: ((CGFloat) -> Void)? = nil,
        showAdvanced: Bool = false
    ) {
        self.model = model
        self.onSizeChange = onSizeChange
        _showAdvanced = State(initialValue: showAdvanced)
    }

    private var hostingScreen: NSScreen? {
        NSApp.keyWindow?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
    }

    private var maxScrollHeight: CGFloat {
        let screenHeight = hostingScreen?.visibleFrame.height ?? 900
        return min(640, max(340, screenHeight - 180))
    }

    private var scrollHeight: CGFloat {
        min(max(scrollContentHeight, 160), maxScrollHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, sideInset)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ScrollView(.vertical) {
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
                .padding(.bottom, 14)
                .frame(width: Theme.panelWidth, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .scrollIndicators(.visible)
            .frame(width: Theme.panelWidth)
            .frame(height: scrollHeight)
            .onPreferenceChange(ContentHeightKey.self) { height in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if abs(height - scrollContentHeight) > 0.5 {
                        scrollContentHeight = height
                    }
                }
            }

            if scrollContentHeight > scrollHeight + 8 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Scroll")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
                .accessibilityLabel("More content is available. Scroll to see it.")
            }

            footer
        }
        .frame(width: Theme.panelWidth)
        .background(panelBackground)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PanelHeightKey.self,
                    value: proxy.size.height
                )
            }
        )
        .onPreferenceChange(PanelHeightKey.self) { height in
            onSizeChange?(height)
        }
        .onAppear {
            model.start()
            model.refreshLaunchAtLogin()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)

            Text("LidAwake")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .frame(height: 20)
    }

    // MARK: - Primary control

    private var primaryModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Keep this Mac awake")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

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
                            .padding(.top, 1)
                    }

                    if model.externalSleepDisabled && !model.externalSession {
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
                            .buttonStyle(NoticeActionStyle(tint: Theme.warningText))
                            .focused($clearFocused)
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: Theme.rowRadius,
                                    style: .continuous
                                )
                                .strokeBorder(
                                    Color.accentColor.opacity(clearFocused ? 0.9 : 0),
                                    lineWidth: 2
                                )
                            )
                            .accessibilityHint("Clears the sleep setting that was changed outside LidAwake.")
                        }
                    }

                    if let note = model.presentation.eventNote {
                        Label(note, systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 1)
                            .transition(.opacity)
                    }
                }

                Spacer(minLength: 4)

                Toggle("", isOn: activeBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .tint(Theme.activeTrack)
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

            if model.isActive {
                activeSessionLine
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(primaryBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.primaryRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.06),
            radius: 10,
            x: 0,
            y: 3
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86),
            value: model.isActive
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: model.presentation.stateLabel
        )
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
                        .scaleEffect(x: 1, y: 0.8, anchor: .center)
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
        if model.presentation.isWarning { return Theme.warningText }
        return Theme.secondaryText
    }

    private var dotColor: Color {
        if model.presentation.isWarning { return statusTextColor }
        if model.isActive { return Theme.activeText }
        if model.isStopping || model.externalSession { return Theme.warningText }
        return Theme.secondaryText
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
                action: { DiagnosticsWindowController.shared.show(model: model) },
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
                actionTitle: model.isActive ? nil : "Try Again",
                action: model.isActive ? nil : { model.arm() },
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
                mode: effectiveMode,
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
                    mode: effectiveMode,
                    duration: model.externalLease?.deadline.map {
                        $0.timeIntervalSince(model.externalLease?.startedAt ?? Date())
                    },
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
        mode: SleepMode,
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
                SettingsValueRow(title: "Sleep control", value: mode.friendlyName)
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
                withAnimation(
                    reduceMotion
                        ? nil
                        : .spring(response: 0.34, dampingFraction: 0.88)
                ) {
                    showAdvanced.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Advanced")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.18),
                            value: showAdvanced
                        )
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 8)
                .frame(height: 44)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                        .fill(Color.primary.opacity(advancedHovered ? 0.045 : 0))
                )
            }
            .buttonStyle(RowPressStyle())
            .focused($advancedFocused)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(advancedFocused ? 0.9 : 0),
                        lineWidth: 2
                    )
            )
            .onHover { advancedHovered = $0 }
            .accessibilityLabel("Advanced")
            .accessibilityValue(showAdvanced ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows sleep control, Open at Login, and diagnostics.")

            if showAdvanced {
                advancedContent
                    .transition(.opacity)
            }
        }
    }

    private var advancedContent: some View {
        VStack(spacing: 0) {
            GroupDivider()

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

            if effectiveMode == .system, !model.fallbackInstalled,
               !model.isActive, !model.externalSession {
                Button("Set Up…") {
                    model.revealFallbackInstaller()
                }
                .buttonStyle(NoticeActionStyle(tint: Theme.warningText))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .help("Shows the one-time administrator setup script in Finder.")
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

            Button {
                DiagnosticsWindowController.shared.show(model: model)
            } label: {
                HStack(spacing: 8) {
                    Text("Diagnostics…")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(height: 38)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                        .fill(Color.primary.opacity(diagnosticsHovered ? 0.035 : 0))
                        .padding(.horizontal, 6)
                )
            }
            .buttonStyle(RowPressStyle())
            .focused($diagnosticsFocused)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(diagnosticsFocused ? 0.9 : 0),
                        lineWidth: 2
                    )
            )
            .onHover { diagnosticsHovered = $0 }
            .accessibilityLabel("Open Diagnostics")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)

            HStack(spacing: 10) {
                if model.isActive {
                    Text("Keep the Mac on a hard, ventilated surface.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .transition(.opacity)
                }

                Spacer(minLength: 4)

                Button {
                    model.quit()
                } label: {
                    Label("Quit", systemImage: "power")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                                .fill(Color.primary.opacity(quitHovered ? 0.06 : 0))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .focused($quitFocused)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                        .strokeBorder(
                            Color.accentColor.opacity(quitFocused ? 0.9 : 0),
                            lineWidth: 2
                        )
                )
                .onHover { quitHovered = $0 }
                .disabled(model.isBusy)
                .accessibilityLabel("Quit LidAwake")
                .help("Quits LidAwake, restores its own session, and removes runtime helpers. External sleep flags are left untouched.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: model.isActive
        )
    }

    // MARK: - Background

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.regularMaterial)
    }
}


