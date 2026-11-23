import SwiftUI
import AppKit

extension Notification.Name {
    static let lidAwakeDiagnosticsRefresh = Notification.Name("LidAwakeDiagnosticsRefresh")
}

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    var onClose: (() -> Void)? = nil
    @State private var text = ""
    @State private var copyFeedback: String?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Diagnostics")
                    .font(.headline)
                Spacer()
                if let copyFeedback {
                    Text(copyFeedback)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .transition(.opacity)
                }
                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    copy()
                } label: {
                    Label("Copy", systemImage: "document.on.document")
                }
                Button("Done") {
                    if let onClose {
                        onClose()
                    } else {
                        NSApp.keyWindow?.performClose(nil)
                    }
                }
                .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.bordered)
            .padding(16)

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(minWidth: 400, minHeight: 260)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .lidAwakeDiagnosticsRefresh)) { _ in
            refresh()
        }
        .onDisappear { feedbackTask?.cancel() }
    }

    private func refresh() {
        text = model.diagnostics
        feedbackTask?.cancel()
        copyFeedback = nil
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(text, forType: .string)
        copyFeedback = copied ? "Copied" : "Copy failed"
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.5))
                copyFeedback = nil
            } catch {
                // A newer copy action or a closing window superseded this one.
            }
        }
    }
}
