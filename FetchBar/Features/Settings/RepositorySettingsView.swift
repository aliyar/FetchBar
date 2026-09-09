import SwiftUI
import UniformTypeIdentifiers

struct RepositorySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var addApplicationError: String?

    var body: some View {
        @Bindable var settings = model.settings
        Section {
            Picker("Default application", selection: $settings.defaultOpenAppBundleID) {
                ForEach(model.openApps) { app in
                    Label {
                        Text(app.name)
                    } icon: {
                        if let icon = OpenInService.icon(for: app) { Image(nsImage: icon) }
                    }
                    .tag(app.id)
                }
            }
            ForEach(model.openApps.filter { $0.kind == .custom }) { app in
                LabeledContent {
                    Button("Remove") { model.removeCustomOpenApp(app.id) }.controlSize(.small)
                } label: {
                    HStack {
                        if let icon = OpenInService.icon(for: app) { Image(nsImage: icon) }
                        Text(app.name)
                    }
                }
            }
            LabeledContent {
                Button("Add Application…") { chooseApplication() }.controlSize(.small)
            } label: {
                Text("Any application that is not in the list")
                    .foregroundStyle(.secondary)
            }
            if let error = addApplicationError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        } header: {
            Text("Open In")
        } footer: {
            Footnote("Used for repositories you have not opened yet. Afterwards each repository remembers the app you last opened it with, so the button is already right the next time.")
        }

        Section {
            ForEach(settings.watchedFolders, id: \.self) { folder in
                LabeledContent {
                    Button("Remove") { model.removeWatchedFolder(folder) }.controlSize(.small)
                } label: {
                    Label((folder as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            LabeledContent {
                Button("Add Folder…") { chooseWatchedFolder() }.controlSize(.small)
            } label: {
                Text("A folder that holds your clones")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Watched Folders")
        } footer: {
            Footnote("Clones added to a watched folder show up in FetchBar on their own. Nothing is removed for you.")
        }
    }

    /// Picks a folder whose clones should be added automatically.
    private func chooseWatchedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder that holds your clones"
        panel.prompt = "Watch"
        let developer = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Developer")
        panel.directoryURL = FileManager.default.fileExists(atPath: developer.path) ? developer : URL(fileURLWithPath: NSHomeDirectory())
        AppActivation.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addWatchedFolder(url)
    }

    /// Lets the user point at any application the built-in catalog does not list.
    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an application to open repositories in"
        panel.prompt = "Add"
        AppActivation.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let app = model.addCustomOpenApp(at: url) else {
            addApplicationError = "\(url.deletingPathExtension().lastPathComponent) has no bundle identifier"
            return
        }
        addApplicationError = nil
        model.settings.defaultOpenAppBundleID = app.id
    }
}
