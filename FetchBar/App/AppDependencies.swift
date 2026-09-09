import AppKit
import SwiftUI
import OSLog
import GitEngine

/// Composition root. Created in `applicationWillFinishLaunching`, before any scene exists.
final class AppDependencies {
    private(set) static var shared: AppDependencies!

    let settings: AppSettings
    let hotKey = GlobalHotKey()
    let engine: RepoEngine
    let model: AppModel
    let statusItem: StatusItemController
    let notifications: NotificationManager
    let loginItem: LoginItemController
    let triggers: SystemTriggers
    let updates: UpdateController
    let settingsWindow: SettingsWindowController
    let panelUI = PanelUIState()
    private var observationTask: Task<Void, Never>?

    private init() {
        settings = AppSettings()
        engine = RepoEngine(settings: settings.engineSettings)
        model = AppModel(engine: engine, settings: settings)
        statusItem = StatusItemController()
        notifications = NotificationManager()
        loginItem = LoginItemController()
        triggers = SystemTriggers(model: model)
        updates = UpdateController()
        let model = model, settings = settings, loginItem = loginItem
        let notifications = notifications, updates = updates
        settingsWindow = SettingsWindowController(
            size: SettingsShell<FetchBarSettingsPane, EmptyView>.size,
            minimumSize: SettingsShell<FetchBarSettingsPane, EmptyView>.minimumSize,
            initialPane: FetchBarSettingsPane.general
        ) { selection in
            AnyView(SettingsView(selection: selection)
                .environment(model).environment(settings)
                .environment(loginItem).environment(notifications).environment(updates))
        }
        wire()
    }

    static func bootstrap() {
        guard shared == nil else { return }
        shared = AppDependencies()
    }

    private func wire() {
        let model = model
        let statusItem = statusItem
        let notifications = notifications
        let panelUI = panelUI
        let updates = updates

        statusItem.panelRoot = { [model, panelUI, updates] in
            AnyView(MenuBarPanel().environment(model).environment(panelUI).environment(updates))
        }
        statusItem.onInstallUpdate = { updates.checkForUpdates() }
        statusItem.onRefreshAll = { model.refreshAll() }
        statusItem.onMarkAllSeen = { model.markAllSeen() }
        statusItem.onTogglePause = { model.togglePause() }
        statusItem.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        statusItem.onQuit = { NSApp.terminate(nil) }
        statusItem.onPanelOpened = {
            panelUI.selected = nil
            model.panelDidOpen()
        }
        settings.onPanelShortcutChange = { [weak self] in self?.applyPanelShortcut() }

        model.closePanel = { statusItem.closePopover() }
        model.onNotify = { record, snapshot in notifications.post(record: record, snapshot: snapshot) }
        model.onNotifyUnpushed = { record, snapshot in notifications.postUnpushed(record: record, snapshot: snapshot) }
        model.onRepositoriesAvailable = { [settings] in
            guard settings.notificationsEnabled else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                await notifications.ensureAuthorized()
            }
        }

        notifications.onShowRepository = { [panelUI] id in
            panelUI.expanded.insert(id)
            statusItem.showPopover()
        }
        notifications.onOpenRepository = { id in model.open(id) }
        notifications.onPull = { id in model.pull(id) }
        notifications.onInstallUpdate = { updates.checkForUpdates() }

        updates.onUpdateAvailable = { [settings] version in
            statusItem.updateAvailableVersion = version
            if settings.notificationsEnabled { notifications.postUpdateAvailable(version: version) }
        }
    }

    func start() {
        model.start()
        registerLoginItemOnFirstRun()
        model.scanWatchedFolders(force: true)
        triggers.start()
        observeMenuBarState()
        observeAppearance()
        applyPanelShortcut()
        observeUpdateState()
        updates.start()
        Log.ui.notice("FetchBar started")
    }

    /// Starts at login out of the box. The app only checks while it runs, so a copy that does
    /// not come back after a restart is a copy that quietly stopped working, and the dots go
    /// stale without saying so. macOS announces the new login item itself, and Settings turns
    /// it off in one click.
    ///
    /// Once only, so turning it off stays off. Never from a disk image or a translocated copy:
    /// the path registered there is gone by the next boot, which would leave a broken entry in
    /// Login Items that is far harder to explain than the one we skipped.
    private func registerLoginItemOnFirstRun() {
        // A disk image or a translocated copy is somewhere the app is only passing through, and
        // the path registered from there is gone by the next boot. Leave without spending the
        // one chance, so the copy that lands in Applications still gets the default.
        let path = Bundle.main.bundleURL.path
        guard !path.hasPrefix("/Volumes/"), !path.contains("/AppTranslocation/") else {
            Log.ui.notice("not registering a login item from \(path, privacy: .public)")
            return
        }
        guard !settings.didOfferLoginItem else { return }
        settings.didOfferLoginItem = true
        // `status` starts at .notRegistered and only a refresh makes it true. Already enabled
        // means there is nothing to do; approval pending means someone switched it off in
        // System Settings, and registering again neither works nor takes the hint. Both are
        // settled answers, so the chance is spent either way.
        loginItem.refresh()
        guard !loginItem.isEnabled, !loginItem.requiresApproval else { return }
        loginItem.register()
        Log.ui.notice("registered the login item on first run")
    }

    /// Mirrors "update available" into the status item menu and clears the notification when handled.
    private func observeUpdateState() {
        let version = withObservationTracking {
            updates.availableVersion
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeUpdateState() }
        }
        statusItem.updateAvailableVersion = version
        if version == nil { notifications.clearUpdateNotification() }
    }

    /// (Re-)registers the global shortcut that opens the panel.
    private func applyPanelShortcut() {
        let statusItem = statusItem
        hotKey.onPress = { statusItem.togglePopover() }
        if !hotKey.register(settings.panelShortcut), let shortcut = settings.panelShortcut {
            model.showToast("\(shortcut.displayString) is already used by another app", kind: .failure)
        }
    }

    /// Applies the user's appearance choice to the popover and the Settings window.
    private func observeAppearance() {
        let appearance = withObservationTracking {
            settings.appearance
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAppearance() }
        }
        statusItem.appearance = appearance.nsAppearance
        settingsWindow.appearance = appearance.nsAppearance
    }

    /// Re-renders the status item whenever the derived menu bar state changes.
    private func observeMenuBarState() {
        let state = withObservationTracking {
            model.menuBar
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeMenuBarState() }
        }
        statusItem.state = state
    }
}
