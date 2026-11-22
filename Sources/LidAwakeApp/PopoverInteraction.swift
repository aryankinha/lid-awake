import Foundation

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
        guard let pendingHeight, pendingHeight != currentHeight else { return nil }
        return pendingHeight
    }
}

enum PopoverDismissal {
    static func isOutside(_ point: CGPoint, popoverFrame: CGRect, anchorFrame: CGRect) -> Bool {
        !popoverFrame.contains(point) && !anchorFrame.contains(point)
    }
}
