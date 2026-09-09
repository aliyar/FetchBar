import AppKit

// No SwiftUI `App` scene: the only window FetchBar has is the Settings window, and it is an
// NSWindow of its own, so the SwiftUI `Settings` scene and its fragile "showSettingsWindow:"
// action are not needed. The delegate builds everything after launch.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
