import AppKit

enum AppActivation {
    /// Cooperative activation (macOS 14+). Falls back to the legacy forceful variant when the
    /// cooperative request is refused, which happens for accessory apps that were not the
    /// last-interacted app (e.g. when a notification action or a menu bar click triggers us).
    static func activate() {
        NSApp.activate()
        if !NSApp.isActive {
            // Legacy forceful activation. Deprecated in macOS 14 ("may have no effect"), but it is
            // still what makes an accessory app's window come forward after a status-item click
            // on macOS 14–26 (verified), so it is called through a selector to avoid the warning.
            let selector = NSSelectorFromString("activateIgnoringOtherApps:")
            if NSApp.responds(to: selector) {
                NSApp.perform(selector, with: true)
            }
        }
    }
}
