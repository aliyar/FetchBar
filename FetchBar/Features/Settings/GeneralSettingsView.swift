import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(LoginItemController.self) private var loginItem
    @Environment(UpdateController.self) private var updates

    var body: some View {
        @Bindable var settings = model.settings
        @Bindable var loginItem = loginItem
        @Bindable var updates = updates
        Group {
            Section {
                Picker("Check every", selection: $settings.checkIntervalSeconds) {
                    ForEach(AppSettings.intervalChoices, id: \.self) { seconds in
                        Text(Self.intervalLabel(seconds)).tag(seconds)
                    }
                }
            } footer: {
                Footnote("Repositories are checked on this interval, a few at a time. Opening the panel and waking your Mac check them too.")
            }

            Section {
                Toggle("Launch at login", isOn: $loginItem.isEnabled)
                if loginItem.requiresApproval {
                    LabeledContent {
                        Button("Open Login Items") { loginItem.openSystemSettings() }
                            .controlSize(.small)
                    } label: {
                        Text("Approve FetchBar in System Settings › Login Items")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = loginItem.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            } footer: {
                Footnote("FetchBar checks only while it runs, so starting at login is what keeps the dots current.")
            }

            Section {
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecksForUpdates)
                    .disabled(!updates.isStarted)
                UpdateCheckRow()
            } header: {
                Text("Updates")
            } footer: {
                Footnote("Once a day. A new version is announced in the panel and in a notification, never with a window that takes over what you were doing.")
            }
        }
        .onAppear { loginItem.refresh() }
    }

    static func intervalLabel(_ seconds: Int) -> String {
        seconds < 3600 ? "\(seconds / 60) min" : "\(seconds / 3600) hour"
    }
}
