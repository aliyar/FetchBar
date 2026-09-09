import SwiftUI

struct AboutView: View {
    var body: some View {
        AboutPane(website: SettingsView.website, extra: AnyView(extra))
    }

    /// What About adds to the pane every app in the family shares: where the source is,
    /// and the one control people come to About for.
    @ViewBuilder
    private var extra: some View {
        LabeledContent("Source") {
            Link("github.com/aliyar/FetchBar", destination: URL(string: "https://github.com/aliyar/FetchBar")!)
        }
        LabeledContent("License") { Text("MIT") }
        UpdateCheckRow()
    }
}

/// Checking for updates, and what came of the last check. Shown in General under Updates
/// and again in About, where people look for it.
struct UpdateCheckRow: View {
    @Environment(UpdateController.self) private var updates

    var body: some View {
        if let version = updates.availableVersion {
            LabeledContent {
                Button("Install…") { updates.checkForUpdates() }
                    .keyboardShortcut(.defaultAction)
            } label: {
                Label("FetchBar \(version) is available", systemImage: "sparkles")
                    .foregroundStyle(Color.accentColor)
            }
        } else {
            LabeledContent {
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
            } label: {
                if let date = updates.lastCheckDate {
                    RelativeTimeText(date: date, prefix: "Last checked ")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not checked yet").foregroundStyle(.secondary)
                }
            }
        }
    }
}
