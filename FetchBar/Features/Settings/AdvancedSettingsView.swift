import SwiftUI
import GitEngine

struct AdvancedSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Section {
            LabeledContent("Detected git") {
                if let installation = model.gitInstallation {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(installation.version).font(.callout)
                        Text(installation.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } else if model.gitDiscoveryFinished {
                    Text("Not found").foregroundStyle(.red)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            HStack {
                TextField("Custom git path (optional)", text: $settings.gitPathOverride, prompt: Text("/opt/homebrew/bin/git"))
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseGit() }
            }
            TextField("Extra PATH entries (colon-separated)", text: $settings.extraPaths, prompt: Text("/usr/local/bin:~/.cargo/bin"))
                .textFieldStyle(.roundedBorder)
        } header: {
            Text("Git")
        } footer: {
            Footnote("Credential helpers such as `gh` or `git-credential-manager` must be reachable on PATH.")
        }

        Section {
            Picker("Fetch timeout", selection: $settings.fetchTimeoutSeconds) {
                ForEach(AppSettings.fetchTimeoutChoices, id: \.self) { Text("\($0) s").tag($0) }
            }
            Stepper("Max concurrent checks: \(settings.maxConcurrentChecks)", value: $settings.maxConcurrentChecks, in: 1...8)
            Toggle("Probe with ls-remote before fetching", isOn: $settings.probeBeforeFetch)
            Toggle("Prune deleted remote branches when fetching", isOn: $settings.pruneOnFetch)
        } header: {
            Text("Checking")
        } footer: {
            Footnote("Probing asks the server for the branch tip first and fetches only when it moved, so nothing is written to your repository otherwise.")
        }

        Section {
            LabeledContent {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([RepoPersistence.defaultDirectory()])
                }
                .controlSize(.small)
            } label: {
                Text("Repository list and check cache")
            }
        } header: {
            Text("Data")
        } footer: {
            Footnote("Two JSON files in Application Support › FetchBar. Delete them and FetchBar starts empty.")
        }
    }

    private func chooseGit() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        panel.message = "Choose the git executable"
        AppActivation.activate()
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.gitPathOverride = url.path
        }
    }
}
