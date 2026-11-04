import Foundation
import Testing

@testable import Heraldr

@Suite("Target card: the state of the target and what a new send will do")
struct TargetCardTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let workspace: String
        let tab: String?
        let state: String
        let next: String

        var testDescription: String { tab ?? workspace }
    }

    static let cases: [Case] = [
        Case(workspace: "wA", tab: nil, state: "Ready", next: "A send clears its context, then hands over the request."),
        Case(workspace: "wH", tab: nil, state: "Working", next: "A new send will wait until it finishes its work."),
        Case(workspace: "wS", tab: nil, state: "Sending…", next: "A new send will go out right after."),
        Case(workspace: "wM", tab: nil, state: "Ready", next: "A send clears its context, then hands over the request."),
        Case(workspace: "wL", tab: nil, state: "Unknown state", next: "A new send will wait until it is ready."),
        Case(workspace: "wB", tab: nil, state: "No agent yet", next: "A send will start Claude in tab 1, named blog-main."),
        Case(
            workspace: "wK", tab: nil, state: "Several -main Claudes",
            next: "A send will fail: keep only one of w---morris-main, morris_api-main, or name it morris-main."),
        Case(
            workspace: "wH", tab: "wH:t2", state: "Ready", next: "A send hands over the request as is, keeping its context."),
        Case(
            workspace: "wH", tab: "wH:t4", state: "Asking you a question: answer in Claude mobile",
            next: "A new send will wait until you have answered it."),
    ]

    @MainActor
    @Test("each target of the demo Mac tells its state and what a new send will do", arguments: cases)
    func targetCard(_ expected: Case) async throws {
        let model = AppModel(environment: .fake(.demo, suiteName: "heraldr-tests-\(UUID().uuidString)"))
        await model.refresh()
        let workspace = try #require(model.workspaces.first { $0.id == expected.workspace })
        let tab = try expected.tab.map { id in try #require(model.tabs.first { $0.id == id }) }
        let target = Target(workspace, tab: tab)

        let state = model.targetState(for: target)

        #expect(state.headline == expected.state)
        #expect(state.nextSend(to: target) == expected.next)
    }
}
