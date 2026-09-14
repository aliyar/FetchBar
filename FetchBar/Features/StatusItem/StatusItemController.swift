import AppKit
import SwiftUI
import OSLog

/// A pane over the item's button that takes a drop.
///
/// The button is the system's and cannot be given dragged types of its own, so this sits
/// over it: transparent, invisible to the pointer (`hitTest` answers nil, so clicks go
/// through), and awake only while something is being dragged.
private final class DropCatcher: NSView {
    private let accept: ([URL]) -> Bool
    private let over: (Bool) -> Void
    private var isReceiving = false {
        didSet { if isReceiving != oldValue { needsDisplay = true } }
    }

    init(frame: NSRect, over: @escaping (Bool) -> Void, accept: @escaping ([URL]) -> Bool) {
        self.over = over
        self.accept = accept
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Folders only: a repository is a folder, and a file dragged past the icon is not
    /// something FetchBar could watch.
    private func folders(in dragging: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = dragging.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !folders(in: sender).isEmpty else { return [] }
        isReceiving = true
        over(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isReceiving = false
        over(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isReceiving = false
        let found = folders(in: sender)
        guard !found.isEmpty else {
            over(false)
            return false
        }
        return accept(found)
    }

    /// A ring while something is over it, since the item cannot highlight itself for a
    /// drag the way it does for a click.
    override func draw(_ dirtyRect: NSRect) {
        guard isReceiving else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 3), xRadius: 4, yRadius: 4)
        ring.lineWidth = 2
        ring.stroke()
    }
}

/// Owns the `NSStatusItem` and the `NSPopover` that hosts the SwiftUI panel.
/// All public API is main-actor; AppKit callbacks hop back onto the main actor explicitly.
final class StatusItemController: NSObject, NSPopoverDelegate {
    // MARK: Inputs
    var state = MenuBarState() {
        didSet { if state != oldValue { render() } }
    }
    /// Builds the SwiftUI root of the popover. Set before `install()`.
    var panelRoot: (() -> AnyView)?

    // MARK: Callbacks (wired by AppDependencies)
    var onRefreshAll: (() -> Void)?
    var onMarkAllSeen: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var onPanelOpened: (() -> Void)?
    var onPanelClosed: (() -> Void)?
    var onInstallUpdate: (() -> Void)?
    /// Folders dropped on the item. Answers whether they were taken.
    var onDrop: (([URL]) -> Bool)?
    /// A folder is being dragged over the item, or has left it again. Dropping onto a menu
    /// bar icon is a gesture with no affordance, so the app gets the chance to say the icon
    /// will take it.
    var onDragOver: ((Bool) -> Void)?
    /// Version string of an available app update (adds an item to the context menu).
    var updateAvailableVersion: String?
    /// nil → follow the system. Applied to the popover only, so the status item glyph
    /// keeps matching the menu bar rather than the app's chosen theme.
    var appearance: NSAppearance? {
        didSet {
            popover.appearance = appearance
            dropPanel?.appearance = appearance
        }
    }

    // MARK: Private
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    /// The drop panel, which hangs off the same button and is held to the same rule: the
    /// image waits while it is up, or the dots changing under a drop would close it.
    private var dropPanel: NSPopover?
    private let renderer = StatusItemRenderer()
    private var appearanceObservation: NSKeyValueObservation?
    private var lastRendered: (layout: StatusItemLayout, dark: Bool, scale: CGFloat)?
    private var renderPending = false
    private var globalMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?

    var isPopoverShown: Bool { popover.isShown }

    // MARK: Lifecycle

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = []
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.render() }
            }
            let catcher = DropCatcher(frame: button.bounds) { [weak self] isOver in
                self?.onDragOver?(isOver)
            } accept: { [weak self] urls in
                self?.onDrop?(urls) ?? false
            }
            button.addSubview(catcher)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: panelRoot?() ?? AnyView(EmptyView()))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        render()
        Log.statusItem.info("status item installed")
    }

    /// Re-renders the status item image. Replacing the button image while the popover is shown makes
    /// AppKit dismiss the popover, so visual changes are deferred until it closes; non-visual state
    /// changes (e.g. "checking") never touch the image at all.
    func render() {
        guard let button = statusItem?.button else { return }
        if popover.isShown || dropPanel?.isShown == true {
            renderPending = true
            return
        }
        if button.toolTip != state.summary {
            button.toolTip = state.summary
            button.setAccessibilityLabel(state.summary)
        }
        let layout = StatusItemLayout.make(from: state)
        let scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let last = lastRendered, last.layout == layout, last.dark == dark, last.scale == scale { return }
        let image = renderer.image(for: layout, appearance: button.effectiveAppearance, scale: scale)
        button.image = image
        lastRendered = (layout, dark, scale)
        renderPending = false
        dumpIfRequested(image, layout: layout)
    }

    /// Debug aid: `FETCHBAR_DUMP_STATUS_IMAGE=/path/prefix` writes light+dark renders as PNG.
    private func dumpIfRequested(_ image: NSImage?, layout: StatusItemLayout) {
        guard let prefix = ProcessInfo.processInfo.environment["FETCHBAR_DUMP_STATUS_IMAGE"] else { return }
        for (name, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            guard let img = renderer.image(for: layout, appearance: appearance, scale: 2),
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
        }
        if let image { Log.statusItem.debug("status image size \(image.size.width)x\(image.size.height)") }
    }

    // MARK: Popover

    func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        closeDropPanel()
        AppActivation.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        button.highlight(true)
        installMonitors()
        if !NSApp.isActive { makePopoverKeyWhenActive() }
        Log.statusItem.debug("popover shown; appActive=\(NSApp.isActive)")
        onPanelOpened?()
    }

    func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    func togglePopover() {
        popover.isShown ? closePopover() : showPopover()
    }

    func popoverDidClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === popover else {
            if renderPending { render() }
            return
        }
        Log.statusItem.debug("popover closed")
        statusItem?.button?.highlight(false)
        removeMonitors()
        onPanelClosed?()
        if renderPending { render() }
    }

    // MARK: Drop panel

    var isDropPanelShown: Bool { dropPanel?.isShown == true }

    /// Shows the drop panel under the item, building it on first use. `makeKey` lets its
    /// buttons answer to Return and Escape once the drop has landed.
    func showDropPanel(makeKey: Bool, content: () -> AnyView) {
        guard let button = statusItem?.button else { return }
        closePopover()
        let panel = dropPanel ?? makeDropPanel(content())
        dropPanel = panel
        if !panel.isShown {
            panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        if makeKey {
            AppActivation.activate()
            panel.contentViewController?.view.window?.makeKey()
        }
    }

    func closeDropPanel() {
        guard let dropPanel, dropPanel.isShown else { return }
        dropPanel.performClose(nil)
    }

    private func makeDropPanel(_ root: AnyView) -> NSPopover {
        let panel = NSPopover()
        // Transient: clicking away is a way out, and nothing is lost by leaving.
        panel.behavior = .transient
        panel.animates = false
        panel.appearance = appearance
        panel.delegate = self
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        return panel
    }

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.closePopover() }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let activateObserver { NotificationCenter.default.removeObserver(activateObserver) }
        activateObserver = nil
    }

    /// Activation is asynchronous; once the app becomes active make the popover key so that
    /// keyboard shortcuts inside the panel work immediately.
    private func makePopoverKeyWhenActive() {
        activateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover.isShown else { return }
                self.popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    // MARK: Clicks & menu

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false)
        if isSecondary {
            closePopover()
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        if let version = updateAvailableVersion {
            menu.addItem(makeItem("Install FetchBar \(version)…", action: #selector(menuInstallUpdate), key: ""))
            menu.addItem(.separator())
        }
        menu.addItem(makeItem("Refresh All", action: #selector(menuRefreshAll), key: "r"))
        menu.addItem(makeItem("Mark All as Seen", action: #selector(menuMarkAllSeen), key: ""))
        menu.addItem(makeItem(state.isPaused ? "Resume Checks" : "Pause Checks", action: #selector(menuTogglePause), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", action: #selector(menuOpenSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit FetchBar", action: #selector(menuQuit), key: "q"))
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func makeItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func menuRefreshAll() { onRefreshAll?() }
    @objc private func menuMarkAllSeen() { onMarkAllSeen?() }
    @objc private func menuTogglePause() { onTogglePause?() }
    @objc private func menuOpenSettings() { onOpenSettings?() }
    @objc private func menuQuit() { onQuit?() }
    @objc private func menuInstallUpdate() { onInstallUpdate?() }
}
