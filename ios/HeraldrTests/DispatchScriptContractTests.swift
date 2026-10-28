import Foundation
import Testing

@testable import Heraldr

@Suite("Contract between the app and dispatch.sh")
struct DispatchScriptContractTests {
    @Test("dispatch.sh status lines become the sends shown by the app")
    func statusLines() {
        let jobs = DispatchJob.parse(
            statusOutput: """
                20261010120000-41-ab12cd34\tw1\thome-main\tqueued\t
                20261010120100-42-ef56ab78\tw5\tnaive-search-main\tfailed\tagent naive-search-main belongs to workspace w9

                """)

        #expect(
            jobs == [
                DispatchJob(id: "20261010120000-41-ab12cd34", workspaceId: "w1", agent: "home-main", state: .queued, error: nil),
                DispatchJob(
                    id: "20261010120100-42-ef56ab78", workspaceId: "w5", agent: "naive-search-main", state: .failed,
                    error: "agent naive-search-main belongs to workspace w9"),
            ])
        #expect(jobs.map(\.isPending) == [true, false])
    }

    @Test("a send the -main answered is flagged by status, an older script without that column stays readable")
    func answeredColumn() {
        let jobs = DispatchJob.parse(statusOutput: "a\tw1\thome-main\tsent\t\tanswered\nb\tw1\thome-main\tsent\t\t\nc\tw1\thome-main\tsent\t\n")

        #expect(jobs.map(\.answered) == [true, false, false])
    }

    @Test("a start from the grid is told apart from a send, an older script without that column only lists sends")
    func kindColumn() {
        let jobs = DispatchJob.parse(
            statusOutput: "a\tw1\thome-main\tqueued\t\t\tstart\nb\tw1\thome-main\tqueued\t\t\tsend\nc\tw1\thome-main\tsent\t\t\n")

        #expect(jobs.map(\.kind) == [.start, .send, .send])
    }

    @Test("read-answer output gives the summary, then the full answer in markdown")
    func readAnswer() throws {
        let answer = try #require(Answer(scriptOutput: "The cache is cleared on every deploy.\n\n## Details\n\nThe `purge` job runs after `deploy`.\n"))

        #expect(answer.summary == "The cache is cleared on every deploy.")
        #expect(answer.body == "## Details\n\nThe `purge` job runs after `deploy`.")
        #expect(Answer(scriptOutput: "\nno summary") == nil)
    }

    @Test("an unknown state from a newer script is ignored without hiding the other sends")
    func unknownState() {
        let jobs = DispatchJob.parse(statusOutput: "a\tw1\thome-main\tcancelled\t\nb\tw1\thome-main\tsending\t\n")

        #expect(jobs.map(\.id) == ["b"])
    }

    @Test("without a script installed on the Mac, no send is listed")
    func noScript() {
        #expect(DispatchJob.parse(statusOutput: "").isEmpty)
    }

    @Test("the Home relay wraps the request exactly as the app does for a project")
    func relayEnvelopeMatchesApp() throws {
        let script = String(decoding: Dispatcher.bundledScript, as: UTF8.self)
        let heredoc = try #require(script.firstMatch(of: #/standard_envelope\(\) \{\n  cat <<EOF\n(?<body>.*?)\nEOF\n/#.dotMatchesNewlines()))
        let project = Workspace(id: "w5", number: 5, label: "Naïve search")

        let shellBody = heredoc.body.replacingOccurrences(of: "\\`", with: "`").replacingOccurrences(of: "\\$", with: "$")
        #expect(PromptEnvelope.wrap("Add a subtitle", for: project) == shellBody.replacingOccurrences(of: "$1", with: "Add a subtitle"))
    }

    @Test("Home and a project both know how to hand the answer to a simple question back to the send that asked it")
    func answerCommand() {
        let home = Workspace(id: "wA", number: 1, label: "Home")
        let project = Workspace(id: "w5", number: 5, label: "Naïve search")

        for workspace in [home, project] {
            #expect(PromptEnvelope.wrap("x", for: workspace).contains("dispatch.sh\" answer \(PromptEnvelope.jobIdPlaceholder)"))
        }
        #expect(!PromptEnvelope.forTab("x").contains("answer"))
    }

    @Test("Home, whatever its label, gets the instructions to relay to the project; a project never gets them")
    func homeEnvelope() {
        let home = Workspace(id: "wA", number: 1, label: "Home")
        let project = Workspace(id: "w5", number: 5, label: "Naïve search")

        #expect(PromptEnvelope.wrap("x", for: home).contains("dispatch.sh\" relay"))
        #expect(!PromptEnvelope.wrap("x", for: project).contains("relay"))
    }

    @Test("a send to a tab warns about possible dictation, without instructions or /start")
    func tabEnvelope() {
        #expect(
            PromptEnvelope.forTab("  The button is too small\n") == """
                Request sent from the iPhone (may come from voice dictation: watch for transcription errors).

                The button is too small
                """)
    }

    @Test("attached screenshots are cited by their path on the Mac, after the text, to a main as to a tab")
    func attachmentsCitedByPath() {
        let project = Workspace(id: "w5", number: 5, label: "Naïve search")
        let paths = ["/Users/me/.local/state/heraldr/attachments/a.jpg", "/Users/me/.local/state/heraldr/attachments/b.jpg"]
        let cited = """
            The button overflows

            Attached screenshots, read them with Read:
            - /Users/me/.local/state/heraldr/attachments/a.jpg
            - /Users/me/.local/state/heraldr/attachments/b.jpg
            """

        #expect(PromptEnvelope.wrap("The button overflows\n", attachments: paths, for: project) == PromptEnvelope.wrap(cited, for: project))
        #expect(PromptEnvelope.forTab("The button overflows", attachments: paths).hasSuffix(cited))
    }

    @Test("Home relays the paths of attached screenshots with the request")
    func homeRelaysAttachments() {
        let home = Workspace(id: "wA", number: 1, label: "Home")
        let prompt = PromptEnvelope.wrap("x", attachments: ["/tmp/a.jpg"], for: home)

        #expect(prompt.contains("- /tmp/a.jpg"))
        #expect(prompt.contains("followed by the paths of the attached screenshots"))
    }
}
