import Observation
import SwiftUI

/// What the menu bar icon says while a folder is dragged over it, and what it asks afterwards.
///
/// Dropping onto a menu bar icon is a gesture with no affordance: nothing on the screen says
/// the icon will take it, and nothing says what happened when it did. So the icon answers
/// with a small panel: an invitation while the pointer is over it, the repositories the drop
/// comes to once it lands, and a word that they were added.
@Observable
final class DropInbox {
    nonisolated struct Candidate: Identifiable, Equatable, Sendable {
        let url: URL
        var id: String { url.standardizedFileURL.path }
        var name: String { url.lastPathComponent }
    }

    enum State: Equatable {
        /// Something is being dragged over the icon, or has landed and is being looked into.
        case inviting
        /// The repositories the drop comes to. Nothing is added until Add.
        case asking([Candidate])
        case adding([Candidate])
        case finished(message: String, succeeded: Bool)
    }

    private(set) var state: State = .inviting

    var isAsking: Bool {
        switch state {
        case .asking, .adding: true
        case .inviting, .finished: false
        }
    }

    var candidates: [Candidate] {
        switch state {
        case .asking(let items), .adding(let items): items
        case .inviting, .finished: []
        }
    }

    /// Something is being dragged over the icon. A question already on the screen is left
    /// alone: what is coming will be added to it.
    func invite() {
        guard !isAsking else { return }
        state = .inviting
    }

    /// What a drop came to. A second drop while the question is still up adds to it rather
    /// than replacing it, since dragging clones over a few at a time is how a drop is used.
    /// `alreadyAdded` counts the dropped repositories FetchBar watches already, so an empty
    /// answer can say which of the two it was.
    func ask(_ repositories: [URL], alreadyAdded: Int, droppedFolder: String?) {
        // Adding is under way; a drop then waits for the next question.
        if case .adding = state { return }
        var items = isAsking ? candidates : []
        for url in repositories {
            let candidate = Candidate(url: url)
            if !items.contains(where: { $0.id == candidate.id }) { items.append(candidate) }
        }
        if !items.isEmpty {
            state = .asking(items)
        } else if alreadyAdded > 0 {
            state = .finished(message: alreadyAdded == 1 ? "Already in FetchBar" : "All \(alreadyAdded) are already in FetchBar",
                              succeeded: true)
        } else {
            state = .finished(message: droppedFolder.map { "No git repositories in \($0)" } ?? "No git repositories there",
                              succeeded: false)
        }
    }

    /// Taken back out before it is added. What was dragged in an armful is not always what was meant.
    func remove(_ id: Candidate.ID) {
        guard case .asking(let items) = state else { return }
        let remaining = items.filter { $0.id != id }
        state = remaining.isEmpty ? .inviting : .asking(remaining)
    }

    /// Add was pressed; the list stays on the screen, disabled, until the engine answers.
    func beginAdding() -> [URL] {
        guard case .asking(let items) = state else { return [] }
        state = .adding(items)
        return items.map(\.url)
    }

    func finish(added: Int, failure: String?) {
        if added > 0 {
            state = .finished(message: added == 1 ? "Added" : "Added \(added) repositories", succeeded: true)
        } else {
            state = .finished(message: failure ?? "Nothing was added", succeeded: false)
        }
    }

    func cancel() {
        state = .inviting
    }
}

/// The panel itself: one thing at a time, hanging off the menu bar icon.
struct DropInboxView: View {
    let inbox: DropInbox
    let onAdd: () -> Void
    let onCancel: () -> Void
    /// More dragged onto the panel itself, which is where the pointer already is once the
    /// panel is up: the icon is a small target and it is now behind this.
    let onDrop: ([URL]) -> Bool

    var body: some View {
        Group {
            switch inbox.state {
            case .inviting: invitation
            case .asking(let items): question(items, busy: false)
            case .adding(let items): question(items, busy: true)
            case .finished(let message, let succeeded): done(message, succeeded: succeeded)
            }
        }
        .frame(width: 270)
        .dropDestination(for: URL.self) { urls, _ in onDrop(urls) }
    }

    /// Room enough to read at a glance while your hand is busy holding a drag.
    private var invitation: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tint)
            Text("Drop to add").font(.headline)
            Text("a repository, or a folder of them")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
    }

    private func question(_ items: [DropInbox.Candidate], busy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(items.count == 1 ? "Add this repository" : "Add \(items.count) repositories")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { candidate in
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(candidate.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help((candidate.url.path as NSString).abbreviatingWithTildeInPath)
                            Spacer(minLength: 4)
                            Button {
                                inbox.remove(candidate.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Leave this one out")
                        }
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
            }
            // Tall enough for a handful, and scrolling after that: a folder of forty clones is
            // still a list you can take one out of.
            .frame(maxHeight: items.count > 5 ? 132 : nil)
            .fixedSize(horizontal: false, vertical: items.count <= 5)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 7))

            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: onAdd)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .disabled(busy)
    }

    private func done(_ message: String, succeeded: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(succeeded ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
    }
}
