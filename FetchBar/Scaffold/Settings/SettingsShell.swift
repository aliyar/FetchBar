import AppKit
import SwiftUI

/// What a Settings pane says about itself in the sidebar.
nonisolated protocol SettingsPane: Hashable, Identifiable, CaseIterable where AllCases: RandomAccessCollection {
    var title: String { get }
    var symbol: String { get }
}

/// Settings laid out like System Settings: a sidebar of panes with the app's name and
/// version at its foot, a grouped form on the right under a title with back and forward
/// buttons that walk the panes visited. The shell is the same in every app; the panes
/// are the app's.
struct SettingsShell<Pane: SettingsPane, Detail: View>: View {
    let selection: SettingsPaneSelection
    @ViewBuilder let detail: (Pane) -> Detail

    static var size: NSSize { NSSize(width: 800, height: 560) }
    static var minimumSize: NSSize { NSSize(width: 700, height: 480) }
    static var sidebarWidth: CGFloat { 220 }

    private var pane: Binding<Pane> {
        Binding(
            get: { selection.pane as? Pane ?? Pane.allCases.first! },
            set: { selection.select($0) }
        )
    }

    var body: some View {
        // The sidebar is always there: no collapse button, no collapsed state.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // The system sidebar, as the App Store's is. The list must not take keyboard
            // focus: a focused list paints its selection in solid accent colour with white
            // text, an unfocused one in the quiet grey with accent text that is wanted here.
            List(selection: pane) {
                ForEach(Array(Pane.allCases)) { item in
                    Label {
                        Text(item.title)
                    } icon: {
                        Image(systemName: item.symbol)
                    }
                    .tag(item)
                }
            }
            .focusable(false)
            .controlSize(.large)
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFooter() }
            // A fixed width, as System Settings has. The column-width modifier alone is not
            // honoured for a split view hosted in an NSWindow of our own (macOS 26), so the
            // content's frame sets the width and the modifier agrees with it.
            .frame(width: Self.sidebarWidth)
            .navigationSplitViewColumnWidth(Self.sidebarWidth)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Form {
                detail(pane.wrappedValue)
            }
            .formStyle(.grouped)
            .navigationTitle(pane.wrappedValue.title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ControlGroup {
                        Button { selection.goBack() } label: { Image(systemName: "chevron.left") }
                            .disabled(!selection.canGoBack)
                            .help("Back")
                        Button { selection.goForward() } label: { Image(systemName: "chevron.right") }
                            .disabled(!selection.canGoForward)
                            .help("Forward")
                    }
                }
            }
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }
}

/// The selected pane and the panes visited before it, shared between the window
/// controller (which may be told to open a given pane) and the shell (whose sidebar and
/// back/forward buttons drive it).
@Observable
final class SettingsPaneSelection {
    private(set) var history: [AnyHashable]
    private(set) var index: Int

    var pane: AnyHashable { history[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < history.count - 1 }

    init(initial: AnyHashable) {
        history = [initial]
        index = 0
    }

    /// Goes to a pane, forgetting anything that was "forward" of here, as a browser does.
    func select(_ pane: AnyHashable) {
        guard pane != self.pane else { return }
        history.removeSubrange((index + 1)...)
        history.append(pane)
        index = history.count - 1
    }

    func goBack() {
        guard canGoBack else { return }
        index -= 1
    }

    func goForward() {
        guard canGoForward else { return }
        index += 1
    }
}

/// The sidebar's foot: the app's icon and name, and its version.
private struct SidebarFooter: View {
    private var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "App" }
    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-" }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 22, height: 22)
            Text(appName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(appVersion)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The About pane every app has: icon, name, version, developer, website.
struct AboutPane: View {
    let website: URL
    var extra: AnyView? = nil

    private var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "App" }
    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-" }
    private var appBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    private var copyright: String { Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "" }

    var body: some View {
        Section {
            HStack(spacing: 14) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName)
                        .font(.title3.weight(.semibold))
                    Text("Version \(appVersion) (\(appBuild))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        Section {
            LabeledContent("Developed by") { Text("GreatPixels") }
            LabeledContent("Website") {
                Link(website.host() ?? website.absoluteString, destination: website)
            }
            if let extra { extra }
            Footnote(copyright)
        }
    }
}

/// The Support pane: a question per row, and the one button that answers it.
struct SupportPane: View {
    struct Row: Identifiable {
        let question: String
        let action: String
        let url: URL
        var id: String { question }
    }

    let intro: String
    let rows: [Row]

    var body: some View {
        Section {
            ForEach(rows) { row in
                LabeledContent(row.question) {
                    Link(row.action, destination: row.url)
                        .buttonStyle(.bordered)
                }
            }
        } header: {
            Text(intro)
                .font(.body)
                .foregroundStyle(.primary)
                .textCase(nil)
                .padding(.bottom, 4)
        }
    }
}

/// The app's icon from its own asset catalogue, never the copy macOS caches for the
/// bundle, which lags behind a new icon until the caches are rebuilt.
private var appIcon: NSImage {
    NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
}

/// The small grey line under a setting that says what it does.
struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
