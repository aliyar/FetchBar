import SwiftUI

/// FetchBar's panes, in the order the sidebar lists them: what you set up first at the top,
/// what you touch once near the bottom, help and identity at the foot.
nonisolated enum FetchBarSettingsPane: String, SettingsPane {
    case general, appearance, menuBar, repositories, notifications, advanced, support, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .menuBar: "Menu Bar"
        case .repositories: "Repositories"
        case .notifications: "Notifications"
        case .advanced: "Advanced"
        case .support: "Support"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .menuBar: "menubar.rectangle"
        case .repositories: "folder"
        case .notifications: "bell"
        case .advanced: "wrench.and.screwdriver"
        case .support: "questionmark.bubble"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    let selection: SettingsPaneSelection

    static let website = URL(string: "https://fetchbar.greatpixels.com")!
    static let supportRows = [
        SupportPane.Row(question: "Have a question?", action: "Visit FAQ", url: URL(string: "https://fetchbar.greatpixels.com/#faq")!),
        SupportPane.Row(question: "Need assistance?", action: "Contact Us", url: URL(string: "mailto:support@greatpixels.com?subject=FetchBar")!),
        SupportPane.Row(question: "Found a bug or have an idea?", action: "Open an Issue", url: URL(string: "https://github.com/aliyar/FetchBar/issues")!),
    ]

    var body: some View {
        SettingsShell(selection: selection) { (pane: FetchBarSettingsPane) in
            switch pane {
            case .general: GeneralSettingsView()
            case .appearance: AppearanceSettingsView()
            case .menuBar: MenuBarSettingsView()
            case .repositories: RepositorySettingsView()
            case .notifications: NotificationSettingsView()
            case .advanced: AdvancedSettingsView()
            case .support: SupportPane(intro: "Get in touch for any feedback, questions or feature requests.", rows: Self.supportRows)
            case .about: AboutView()
            }
        }
    }
}
