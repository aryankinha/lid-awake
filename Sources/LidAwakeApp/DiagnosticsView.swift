import SwiftUI
import AppKit

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    @State private var text = ""
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Diagnostics")
                    .font(.headline)
                Spacer()
                if copied {
                    Text("Copied")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .transition(.opacity)
                }
                Button("Refresh") { refresh() }
                Button("Copy") { copy() }
                Button("Done") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut(.cancelAction)
            }
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
        .frame(width: 560, height: 420)
        .onAppear { refresh() }
    }

    private func refresh() {
        text = model.diagnostics
        copied = false
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
