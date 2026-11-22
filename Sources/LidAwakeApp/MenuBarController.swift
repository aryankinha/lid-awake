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

    init(model: AppModel) {
        self.model = model
        super.init()

        let view = MenuBarView(
            model: model,
            onSizeChange: { [weak self] height in self?.scheduleHeightUpdate(height) },
            onOpenDiagnostics: { [weak self] in self?.popover.close() }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: Theme.panelWidth, height: 470)
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if popover.isShown {
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
        guard heightUpdates.enqueue(height) else { return }
        // Apply only the last measurement from the current SwiftUI layout pass.
        DispatchQueue.main.async {
            guard let height = self.heightUpdates.takeHeight(currentHeight: self.popover.contentSize.height) else { return }
            self.popover.contentSize = NSSize(width: Theme.panelWidth, height: height)
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
