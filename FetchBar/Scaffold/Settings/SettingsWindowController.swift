import AppKit
import SwiftUI

/// One Settings window for the app, created on first use and kept for the rest of the run.
/// Owns the `NSWindow`; the content is whatever SwiftUI view the app hands over.
///
/// A window of our own rather than the SwiftUI `Settings` scene: the scene can only be
/// opened through an undocumented responder action that has changed name across macOS
/// releases, and an accessory app has no menu bar to reach it from anyway.
///
/// Not generic over the pane type on purpose: a generic main-actor class (and a generic
/// `@Observable` one) crashes the Swift 6.3 optimizer's inliner on its `deinit` in Release
/// builds. The pane travels as `AnyHashable` inside `SettingsPaneSelection`.
final class SettingsWindowController {
    /// Bump the suffix when the default size changes, so a frame saved by an older build
    /// does not keep the window at the old size.
    private static let frameName = "SettingsWindow.1"
    private let title: String
    private let size: NSSize
    private let minimumSize: NSSize
    private let content: (SettingsPaneSelection) -> AnyView
    private var window: NSWindow?
    /// nil follows the system. Applied to this window only, never through `NSApp.appearance`,
    /// which would drag the status item along and draw a black glyph on a dark menu bar.
    var appearance: NSAppearance? {
        didSet { window?.appearance = appearance }
    }
    /// The pane on screen and the ones visited before it.
    private let selection: SettingsPaneSelection

    init(title: String = "Settings", size: NSSize, minimumSize: NSSize, initialPane: AnyHashable,
         content: @escaping (SettingsPaneSelection) -> AnyView) {
        self.title = title
        self.size = size
        self.minimumSize = minimumSize
        self.selection = SettingsPaneSelection(initial: initialPane)
        self.content = content
    }

    func show(pane: AnyHashable? = nil) {
        if let pane { selection.select(pane) }
        let window = self.window ?? makeWindow()
        self.window = window
        AppActivation.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        // A standard sidebar runs the full height of the window, under the toolbar.
        window.toolbarStyle = .unified
        window.minSize = minimumSize
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(Self.frameName)
        window.appearance = appearance
        window.contentViewController = NSHostingController(rootView: content(selection))
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        return window
    }
}
