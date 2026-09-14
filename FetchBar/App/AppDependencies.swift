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
    /// What the menu bar icon says while folders are dragged onto it.
    let dropInbox = DropInbox()
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
        statusItem.onDragOver = { [weak self] isOver in self?.dragOverStatusItem(isOver) }
        statusItem.onDrop = { [weak self] urls in self?.acceptDrop(urls) ?? false }
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

    // MARK: Dropping folders on the menu bar icon

    /// A folder dragged over the icon is invited; one that leaves again takes the invitation
    /// with it, while a question that is being answered stays whatever the pointer does.
    private func dragOverStatusItem(_ isOver: Bool) {
        if isOver {
            dropInbox.invite()
            showDropPanel(makeKey: false)
        } else if dropInbox.state == .inviting {
            statusItem.closeDropPanel()
        }
    }

    /// Folders dropped on the icon, or on the drop panel once it is up. Taken at once and
    /// looked into afterwards, because discovery walks the disk and the drag has to be
    /// answered now.
    private func acceptDrop(_ urls: [URL]) -> Bool {
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        guard !folders.isEmpty else {
            if dropInbox.state == .inviting { statusItem.closeDropPanel() }
            return false
        }
        let model = model, inbox = dropInbox
        Task { [weak self] in
            let found = await model.repositories(inDropped: folders)
            inbox.ask(found.repositories, alreadyAdded: found.alreadyAdded,
                      droppedFolder: folders.count == 1 ? folders[0].lastPathComponent : nil)
            Log.ui.notice("\(folders.count, privacy: .public) folders dropped on the icon, \(found.repositories.count, privacy: .public) repositories")
            self?.showDropPanel(makeKey: true)
            if case .finished = inbox.state { self?.closeDropPanelSoon() }
        }
        return true
    }

    private func showDropPanel(makeKey: Bool) {
        let inbox = dropInbox, model = model
        statusItem.showDropPanel(makeKey: makeKey) {
            AnyView(DropInboxView(inbox: inbox) { [weak self] in
                self?.addDroppedRepositories()
            } onCancel: { [weak self] in
                inbox.cancel()
                self?.statusItem.closeDropPanel()
            } onDrop: { [weak self] urls in
                self?.acceptDrop(urls) ?? false
            }
            .environment(model))
        }
    }

    private func addDroppedRepositories() {
        let urls = dropInbox.beginAdding()
        guard !urls.isEmpty else { return }
        let model = model, inbox = dropInbox
        Task { [weak self] in
            let result = await model.addRepositoriesReporting(urls)
            inbox.finish(added: result.added, failure: result.failure)
            Log.ui.notice("added \(result.added, privacy: .public) repositories from a drop")
            self?.closeDropPanelSoon()
        }
    }

    /// Long enough to be read, short enough not to be in the way. A new drag in the meantime
    /// has put something else in the panel, and that stays.
    private func closeDropPanelSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard let self, case .finished = self.dropInbox.state else { return }
            self.statusItem.closeDropPanel()
            self.dropInbox.cancel()
        }
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
