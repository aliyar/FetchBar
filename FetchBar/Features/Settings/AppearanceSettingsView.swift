import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Section {
            Picker("Theme", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        } footer: {
            Footnote("For the panel and this window. The menu bar item follows the menu bar, as every other one does.")
        }

        Section {
            LabeledContent("Open the panel with") {
                HStack(spacing: 8) {
                    if settings.panelShortcut != nil {
                        Button("Clear") { settings.panelShortcut = nil }
                            .controlSize(.small)
                    }
                    ShortcutRecorder(shortcut: $settings.panelShortcut)
                        .frame(width: 116, height: 22)
                }
            }
            Toggle("Refresh when the panel opens", isOn: $settings.refreshOnPanelOpen)
            Toggle("Mark commits as seen when I expand a repository", isOn: $settings.markSeenOnExpand)
        } header: {
            Text("Panel")
        } footer: {
            Footnote("The shortcut works wherever you are, and needs no Accessibility permission. Expanding a repository is how you read its commits, so it is also how you say you have seen them.")
        }
    }
}
