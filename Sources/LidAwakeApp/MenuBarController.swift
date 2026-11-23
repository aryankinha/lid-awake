import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let model: AppModel
    private var iconSubscription: AnyCancellable?
    private var displayedIcon: MenuBarIconModel.Icon?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    private var heightUpdates = PopoverHeightUpdates()
    private var lastMeasuredHeight: CGFloat = 0
    private var previousFrontmostApp: NSRunningApplication?
    private var dismissedByOtherApp = false

    init(model: AppModel) {
        self.model = model
        super.init()

        let screen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        let screenHeight = screen?.visibleFrame.height ?? 900
        let initialHeight = PopoverLayout.initialContentHeight(screenHeight: screenHeight)

        let view = MenuBarView(
            model: model,
            onSizeChange: { [weak self] height in self?.scheduleHeightUpdate(height) },
            onOpenDiagnostics: { [weak self] in self?.popover.close() },
            initialScreenHeight: screenHeight
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: Theme.panelWidth, height: initialHeight)
        lastMeasuredHeight = initialHeight
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        iconSubscription = model.menuIconModel.$state.sink { [weak self] state in
            self?.updateStatusItem(state)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.close()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        model.refreshLaunchAtLogin()
        previousFrontmostApp = NSWorkspace.shared.frontmostApplication
        dismissedByOtherApp = false

        // Apply the last stable content height before the first visible frame.
        // Otherwise the popover opens at the hardcoded size and settles upward
        // after SwiftUI's first layout pass.
        if let hosting = popover.contentViewController as? NSHostingController<MenuBarView> {
            hosting.view.layoutSubtreeIfNeeded()
            let fitted = hosting.view.fittingSize.height
            if fitted.isFinite, fitted > 100 {
                lastMeasuredHeight = fitted.rounded()
            }
        }
        if lastMeasuredHeight > 100 {
            popover.contentSize = NSSize(width: Theme.panelWidth, height: lastMeasuredHeight)
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if popover.isShown {
            // Best effort for older macOS, where an inactive popover can render
            // muted controls. On macOS 27 this is a no-op for an accessory app;
            // the key popover still renders with the active accent.
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            // Make the popover key so its native controls render in the active
            // accent. An accessory app may stay inactive; that is normal and the
            // key popover still renders correctly.
            popover.contentViewController?.view.window?.makeKey()
            button.highlight(true)
            monitorDismissal()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        localClickMonitor = nil
        outsideClickMonitor = nil
        appActivationObserver = nil
        statusItem.button?.highlight(false)

        // Return focus only when LidAwake itself is still frontmost. If the
        // dismissal was an outside click, the clicked app already owns focus.
        let pid = ProcessInfo.processInfo.processIdentifier
        if !dismissedByOtherApp,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
           let previous = previousFrontmostApp,
           previous.processIdentifier != pid {
            if #available(macOS 14.0, *) {
                previous.activate()
            } else {
                previous.activate(options: [.activateIgnoringOtherApps])
            }
        }
        previousFrontmostApp = nil
        dismissedByOtherApp = false
    }

    private func monitorDismissal() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [clicks, .keyDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.type == .keyDown {
                // Native menus handle Escape within their own tracking loop.
                guard event.charactersIgnoringModifiers == "\u{1b}" else { return event }
                self.popover.close()
                return nil
            }
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            self.dismissIfOutside(at: point, window: event.window)
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] event in
            self?.dismissIfOutside(at: event.locationInWindow, window: nil)
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app != NSRunningApplication.current else { return }
            MainActor.assumeIsolated {
                guard let self, self.popover.isShown else { return }
                self.dismissedByOtherApp = true
                self.popover.close()
            }
        }
    }

    private func dismissIfOutside(at point: NSPoint, window: NSWindow?) {
        guard popover.isShown,
              let popoverWindow = popover.contentViewController?.view.window,
              let button = statusItem.button, let statusWindow = button.window else { return }

        // Keep controls and any child panel owned by the popover interactive.
        var target = window
        while let current = target {
            if current === popoverWindow { return }
            target = current.parent
        }
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        if PopoverDismissal.isOutside(point, popoverFrame: popoverWindow.frame, anchorFrame: anchor) {
            popover.close()
        }
    }

    private func scheduleHeightUpdate(_ height: CGFloat) {
        guard height.isFinite, height > 100 else { return }
        lastMeasuredHeight = height.rounded()

        // Cache measurements while the panel is closed, but never resize a
        // window that is not visible. A resize after show is the source of the
        // visible settle.
        guard popover.isShown else { return }
        guard heightUpdates.enqueue(height) else { return }

        // Apply only the last measurement from the current SwiftUI layout pass.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let height = self.heightUpdates.takeHeight(currentHeight: self.popover.contentSize.height),
                  self.popover.isShown else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                self.popover.contentSize = NSSize(width: Theme.panelWidth, height: height)
            }
        }
    }

    private func updateStatusItem(_ state: MenuBarIconModel.State) {
        if displayedIcon != state.icon {
            statusItem.button?.image = state.icon.image
            displayedIcon = state.icon
        }
        statusItem.button?.setAccessibilityLabel(state.accessibilityLabel)
    }
}
