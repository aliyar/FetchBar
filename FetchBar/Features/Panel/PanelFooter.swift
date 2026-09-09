import SwiftUI

struct PanelFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.closePanel?()
                model.presentOpenPanel()
            } label: {
                Label("Add Repository…", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(FooterButton.fill, in: FooterButton.shape)
                    .contentShape(FooterButton.shape)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)
            .help("Add a repository or a folder of repositories (⌘O)")

            Spacer()

            FooterButton(symbol: "gearshape", help: "Settings (⌘,)", action: openSettings)
                .keyboardShortcut(",", modifiers: .command)
            FooterButton(symbol: "power", help: "Quit FetchBar (⌘Q)") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private func openSettings() {
        model.closePanel?()
        AppDependencies.shared.settingsWindow.show()
    }
}

/// The two buttons at the right of the footer: a glyph on a quiet fill, sized so the
/// pointer has something to hit without the words "Settings" and "Quit" competing with
/// the repositories above them.
struct FooterButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    /// Shared with the footer's one text button, so the three read as one row of buttons.
    static let fill = Color.primary.opacity(0.06)
    static let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .background(Self.fill, in: Self.shape)
                .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}
