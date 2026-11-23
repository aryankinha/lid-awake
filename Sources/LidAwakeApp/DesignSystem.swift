import SwiftUI
import AppKit
import LidAwakeCore

enum Theme {
    // Native Apple label hierarchy. Supporting copy uses the system secondary
    // label color; primary status text uses the full label color.
    static let textPrimary = Color.primary
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    // Semantic status colors are for dots and glyphs, never body copy.
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)
    static let accent = Color(nsColor: .controlAccentColor)

    // One neutral system surface and Apple's separator. No state-tinted cards.
    static let hairline = Color(nsColor: .separatorColor)
    static let primaryFill = Color.primary.opacity(0.045)
    static let groupFill = Color.primary.opacity(0.040)

    static let panelWidth: CGFloat = 384
    static let primaryRadius: CGFloat = 16
    static let groupRadius: CGFloat = 14
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 2)
    }
}

struct SessionMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct WarningLine: View {
    let text: String
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.warning)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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

private struct SettingsRowLabel: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 8) {
            SettingsRowLabel(title: title, subtitle: subtitle)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .frame(minHeight: 38)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint(subtitle ?? "")
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
    @Binding var isOn: Bool
    var disabled = false
    var subtitle: String?

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                SettingsRowLabel(title: title, subtitle: subtitle)
                Spacer(minLength: 8)
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .padding(.vertical, subtitle == nil ? 0 : 5)
        .frame(minHeight: 38)
        .disabled(disabled)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
    }
}

struct NoticeBanner: View {
    enum Tone {
        case warning
        case danger

        var tint: Color {
            switch self {
            case .warning: return Theme.warning
            case .danger: return Theme.danger
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
                        .foregroundStyle(Theme.textPrimary)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
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
                            .foregroundStyle(Theme.textSecondary)
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
        case .eightHours: return "8 hours"
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
        guard let seconds else { return "8 hours" }
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
