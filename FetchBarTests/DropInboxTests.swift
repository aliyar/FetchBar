import Foundation
import Testing
@testable import FetchBar

@MainActor
@Suite("Drop inbox")
struct DropInboxTests {
    let alpha = URL(fileURLWithPath: "/tmp/clones/alpha")
    let beta = URL(fileURLWithPath: "/tmp/clones/beta")

    @Test func aSecondDropJoinsTheQuestionWithoutDuplicates() {
        let inbox = DropInbox()
        inbox.ask([alpha], alreadyAdded: 0, droppedFolder: "alpha")
        inbox.ask([alpha, beta], alreadyAdded: 0, droppedFolder: nil)
        #expect(inbox.candidates.map(\.url) == [alpha, beta])

        inbox.invite()
        #expect(inbox.isAsking, "a drag passing over the icon must not throw the question away")
    }

    @Test func removingTheLastOneLeavesNothingToAsk() {
        let inbox = DropInbox()
        inbox.ask([alpha], alreadyAdded: 0, droppedFolder: nil)
        inbox.remove(DropInbox.Candidate(url: alpha).id)
        #expect(inbox.state == .inviting)
        #expect(inbox.beginAdding().isEmpty)
    }

    @Test func anEmptyDropSaysWhichKindOfEmptyItWas() {
        let inbox = DropInbox()
        inbox.ask([], alreadyAdded: 2, droppedFolder: "clones")
        #expect(inbox.state == .finished(message: "All 2 are already in FetchBar", succeeded: true))

        inbox.cancel()
        inbox.ask([], alreadyAdded: 0, droppedFolder: "Documents")
        #expect(inbox.state == .finished(message: "No git repositories in Documents", succeeded: false))
    }

    @Test func addingHoldsTheListUntilTheEngineAnswers() {
        let inbox = DropInbox()
        inbox.ask([alpha, beta], alreadyAdded: 0, droppedFolder: nil)
        #expect(inbox.beginAdding() == [alpha, beta])

        inbox.ask([URL(fileURLWithPath: "/tmp/clones/gamma")], alreadyAdded: 0, droppedFolder: nil)
        #expect(inbox.state == .adding(inbox.candidates), "a drop while adding waits for the next question")

        inbox.finish(added: 2, failure: nil)
        #expect(inbox.state == .finished(message: "Added 2 repositories", succeeded: true))
    }
}
