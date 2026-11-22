import SwiftUI
import AppKit
import LidAwakeCore

enum Theme {
    static let active = Color(nsColor: .systemGreen)
    static let activeTrack = adaptive(
        light: NSColor(srgbRed: 0.118, green: 0.620, blue: 0.431, alpha: 1),
        dark: NSColor(srgbRed: 0.184, green: 0.749, blue: 0.525, alpha: 1)
    )
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)

    static let activeText = adaptive(
        light: NSColor(srgbRed: 0.043, green: 0.420, blue: 0.278, alpha: 1),
        dark: NSColor(srgbRed: 0.357, green: 0.890, blue: 0.659, alpha: 1)
    )
    static let warningText = adaptive(
        light: NSColor(srgbRed: 0.541, green: 0.294, blue: 0.0, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.710, blue: 0.361, alpha: 1)
    )
    static let dangerText = adaptive(
        light: NSColor(srgbRed: 0.702, green: 0.149, blue: 0.118, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.541, blue: 0.502, alpha: 1)
    )

    /// Meaningful secondary copy. Apple's `.secondary` is only ~3:1 on a light
    /// popover, so these tokens keep body/status text at AA contrast.
    static let secondaryText = adaptive(
        light: NSColor(srgbRed: 0.27, green: 0.27, blue: 0.29, alpha: 1),
        dark: NSColor(srgbRed: 0.76, green: 0.76, blue: 0.78, alpha: 1)
    )
    static let tertiaryText = adaptive(
        light: NSColor(srgbRed: 0.38, green: 0.38, blue: 0.40, alpha: 1),
        dark: NSColor(srgbRed: 0.66, green: 0.66, blue: 0.69, alpha: 1)
    )

    static let panelWidth: CGFloat = 360
    static let primaryRadius: CGFloat = 16
    static let groupRadius: CGFloat = 14
    static let hairline = Color.primary.opacity(0.08)
    static let primaryFill = Color.primary.opacity(0.045)
    static let groupFill = Color.primary.opacity(0.035)

    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct SettingsGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            Theme.groupFill,
            in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
        )
    }
}

struct GroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}

struct SettingsRowLabel: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .frame(minHeight: 38)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

struct SettingsMenuChoice: Identifiable, Equatable {
    let id: String
    let title: String
}

struct SettingsMenuRow: View {
    let title: String
    let value: String
    let choices: [SettingsMenuChoice]
    let selectedID: String
    let onSelect: (SettingsMenuChoice) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Picker(
                "",
                selection: Binding(
                    get: { selectedID },
                    set: { id in
                        guard let choice = choices.first(where: { $0.id == id }) else { return }
                        onSelect(choice)
                    }
                )
            ) {
                ForEach(choices) { choice in
                    Text(choice.title).tag(choice.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.regular)
            .fixedSize()
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityHint("Choose a value")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .frame(minHeight: 38)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var disabled = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                SettingsRowLabel(title: title, subtitle: subtitle)
                Spacer(minLength: 8)
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .frame(minHeight: 38)
        .disabled(disabled)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
    }
}

struct SystemStatusLine: View {
    let presentation: SessionPresentation

    var body: some View {
        HStack(spacing: 5) {
            Text(presentation.powerText)
                .foregroundStyle(presentation.isLowBattery ? Theme.warningText : Theme.secondaryText)
            dot
            Text(presentation.thermalText)
                .foregroundStyle(presentation.isThermallyConstrained ? Theme.warningText : Theme.secondaryText)
            dot
            Text(presentation.lidText)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .padding(.horizontal, 16)
        .padding(.top, 1)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Power: \(presentation.powerText). Thermal: \(presentation.thermalText). Lid: \(presentation.lidText)."
        )
    }

    private var dot: some View {
        Text("·")
            .foregroundStyle(Theme.tertiaryText)
            .accessibilityHidden(true)
    }
}

struct NoticeBanner: View {
    enum Tone {
        case warning
        case danger

        var tint: Color {
            switch self {
            case .warning: return Theme.warningText
            case .danger: return Theme.dangerText
            }
        }

        var icon: String {
            switch self {
            case .warning: return "exclamationmark.triangle.fill"
            case .danger: return "exclamationmark.octagon.fill"
            }
        }
    }

    let tone: Tone
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var actionDisabled = false
    var dismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: tone.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone.tint)
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tone.tint)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if actionDisabled {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 2)
                    } else if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)

                if let dismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Dismiss notice")
                }
            }
            .padding(.vertical, 10)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}

extension View {
    func reportHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onChange)
    }
}

struct PanelScrollBehavior: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.3, *) {
            content.scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}

struct PanelScreenReader: NSViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScreenView {
        ScreenView()
    }

    func updateNSView(_ view: ScreenView, context: Context) {
        view.onChange = onChange
        view.reportScreen()
    }

    final class ScreenView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var lastHeight: CGFloat?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self)
            if let window {
                center.addObserver(
                    self, selector: #selector(screenDidChange(_:)),
                    name: NSWindow.didChangeScreenNotification, object: window
                )
                center.addObserver(
                    self, selector: #selector(screenDidChange(_:)),
                    name: NSApplication.didChangeScreenParametersNotification, object: nil
                )
            }
            reportScreen()
        }

        @objc private func screenDidChange(_ notification: Notification) {
            reportScreen()
        }

        func reportScreen() {
            guard let window else { return }
            let screen = window.screen
                ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                ?? NSScreen.main
            guard let height = screen?.visibleFrame.height, height != lastHeight else { return }
            lastHeight = height
            DispatchQueue.main.async { [weak self] in self?.onChange?(height) }
        }
    }
}

extension SleepMode {
    var friendlyName: String {
        switch self {
        case .clamshell: return "Lid close & idle"
        case .system: return "All sleep"
        }
    }

    var friendlyDetail: String {
        switch self {
        case .clamshell: return "Prevents lid-close and idle sleep while active."
        case .system: return "Blocks all sleep, including macOS safety sleep."
        }
    }
}

/// The timer options shown in the panel. "No early auto-off" is represented by
/// the 8-hour choice because every session already has an 8-hour hard cap.
enum TimerChoice: String, CaseIterable, Identifiable {
    case oneHour
    case twoHours
    case fourHours
    case eightHours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .eightHours: return "8 hours (maximum)"
        }
    }

    var preset: TimerPreset {
        switch self {
        case .oneHour: return .oneHour
        case .twoHours: return .twoHours
        case .fourHours: return .fourHours
        case .eightHours: return .eightHours
        }
    }

    init(preset: TimerPreset) {
        switch preset {
        case .off, .eightHours: self = .eightHours
        case .oneHour: self = .oneHour
        case .twoHours: self = .twoHours
        case .fourHours: self = .fourHours
        }
    }

    static func displayDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "8 hours (maximum)" }
        if seconds < 60 {
            return "\(max(1, Int(seconds.rounded()))) sec"
        }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return "\(max(1, minutes)) min"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(hours)h \(remainder)m"
    }
}
