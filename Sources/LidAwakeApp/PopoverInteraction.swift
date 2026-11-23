import Foundation

enum PopoverLayout {
    static let headerHeight: CGFloat = 52
    static let footerHeight: CGFloat = 43
    static let compactScrollHeight: CGFloat = 409

    static func initialContentHeight(screenHeight: CGFloat) -> CGFloat {
        let available = scrollLimit(screenHeight: screenHeight, headerHeight: headerHeight, footerHeight: footerHeight)
        return headerHeight + min(compactScrollHeight, available) + footerHeight
    }

    static func scrollLimit(screenHeight: CGFloat, headerHeight: CGFloat, footerHeight: CGFloat) -> CGFloat {
        max(80, screenHeight - headerHeight - footerHeight - 40)
    }
}

struct PopoverHeightUpdates {
    private var pendingHeight: CGFloat?

    /// Returns whether the caller should schedule a single layout update.
    mutating func enqueue(_ height: CGFloat) -> Bool {
        guard height.isFinite, height > 0 else { return false }
        let needsUpdate = pendingHeight == nil
        // Ignore subpixel layout noise before resizing the AppKit window.
        pendingHeight = height.rounded()
        return needsUpdate
    }

    mutating func takeHeight(currentHeight: CGFloat) -> CGFloat? {
        defer { pendingHeight = nil }
        guard let pendingHeight,
              abs(pendingHeight - currentHeight) >= 1 else { return nil }
        return pendingHeight
    }
}

enum PopoverDismissal {
    static func isOutside(_ point: CGPoint, popoverFrame: CGRect, anchorFrame: CGRect) -> Bool {
        !popoverFrame.contains(point) && !anchorFrame.contains(point)
    }
}
