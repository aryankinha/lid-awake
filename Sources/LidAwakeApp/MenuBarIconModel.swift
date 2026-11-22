import AppKit
import Combine

/// A tiny observable that only changes when the menu bar symbol or its
/// accessibility label changes. The status item observes this instead of
/// AppModel, so the once-per-second UI refresh cannot re-render the status item.
@MainActor
final class MenuBarIconModel: ObservableObject {
    enum Icon {
        case idle
        case active
        case attention

        var image: NSImage {
            let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
                let screen = NSBezierPath(
                    roundedRect: NSRect(x: 3, y: 4.5, width: 16, height: 11),
                    xRadius: 2, yRadius: 2
                )
                NSColor.black.setStroke()
                NSColor.black.setFill()
                screen.lineWidth = 1.5
                screen.stroke()
                NSBezierPath(
                    roundedRect: NSRect(x: 0.75, y: 1.5, width: 20.5, height: 1.6),
                    xRadius: 0.8, yRadius: 0.8
                ).fill()

                switch self {
                case .idle:
                    break
                case .active:
                    let bolt = NSBezierPath()
                    bolt.move(to: NSPoint(x: 11.9, y: 14))
                    bolt.line(to: NSPoint(x: 7.7, y: 9.5))
                    bolt.line(to: NSPoint(x: 10.5, y: 9.5))
                    bolt.line(to: NSPoint(x: 10, y: 6))
                    bolt.line(to: NSPoint(x: 14.3, y: 11))
                    bolt.line(to: NSPoint(x: 11.5, y: 11))
                    bolt.close()
                    bolt.fill()
                case .attention:
                    NSBezierPath(
                        roundedRect: NSRect(x: 10.15, y: 9, width: 1.7, height: 4.5),
                        xRadius: 0.85, yRadius: 0.85
                    ).fill()
                    NSBezierPath(ovalIn: NSRect(x: 10.15, y: 6.3, width: 1.7, height: 1.7)).fill()
                }
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    struct State: Equatable {
        var icon: Icon
        var accessibilityLabel: String
    }

    @Published private(set) var state = State(
        icon: .idle,
        accessibilityLabel: "LidAwake off, normal sleep"
    )

    func update(icon: Icon, accessibilityLabel: String) {
        let newState = State(
            icon: icon,
            accessibilityLabel: accessibilityLabel
        )
        if newState != state {
            state = newState
        }
    }
}
