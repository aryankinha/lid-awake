import Foundation
import Combine

/// A tiny observable that only changes when the menu bar symbol or its
/// accessibility label changes. The MenuBarExtra label observes this instead of
/// AppModel, so the once-per-second UI refresh cannot re-render the status item.
@MainActor
final class MenuBarIconModel: ObservableObject {
    struct State: Equatable {
        var symbol: String
        var accessibilityLabel: String
    }

    @Published private(set) var state = State(
        symbol: "moon.fill",
        accessibilityLabel: "LidAwake off, normal sleep"
    )

    func update(symbol: String, accessibilityLabel: String) {
        let newState = State(
            symbol: symbol,
            accessibilityLabel: accessibilityLabel
        )
        if newState != state {
            state = newState
        }
    }
}
