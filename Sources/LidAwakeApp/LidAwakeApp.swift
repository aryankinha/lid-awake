import SwiftUI

@main
@MainActor
struct LidAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared
    @ObservedObject private var iconModel = AppModel.shared.menuIconModel

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            // Keep the status label a direct Image. A custom @ObservedObject view
            // can be laid out without rasterizing its first image in the
            // MenuBarExtra status item.
            Image(systemName: iconModel.state.symbol)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .frame(width: 18, height: 18)
                .transaction { $0.animation = nil }
                .accessibilityLabel(iconModel.state.accessibilityLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
