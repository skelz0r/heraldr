import Foundation
import Testing

@testable import Heraldr

@Suite("Send history")
struct SendHistoryTests {
    private let workspace = Workspace(id: "w1", number: 2, label: "heraldr")

    @Test("only the last 20 sends are kept, from newest to oldest")
    func keepsOnlyTheTwentyLatestSends() {
        var history = SendHistory()
        for index in 1...25 {
            _ = history.record("send \(index)", to: workspace)
        }

        #expect(history.entries.count == 20)
        #expect(history.entries.first?.text == "send 25")
        #expect(history.entries.last?.text == "send 6")
    }

    @Test("a send still in progress when the app relaunches keeps its text, marked interrupted")
    func interruptedSendSurvivesRelaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: "send-history-\(UUID())"))
        var history = SendHistory()
        _ = history.record("text not to lose", to: workspace)
        SendHistoryStore.save(history, to: defaults)

        let relaunched = SendHistoryStore.load(from: defaults)

        let entry = try #require(relaunched.entries.first)
        #expect(entry.text == "text not to lose")
        #expect(entry.workspaceId == "w1")
        #expect(entry.status == .failed)
        #expect(entry.error == SendHistory.interruptedError)
    }

    @Test("a send refused before reaching the Mac keeps its text and the failure reason")
    func localFailureKeepsText() throws {
        var history = SendHistory()
        let id = history.record("request", to: workspace)

        history.fail(id, error: "Mac unreachable")

        let entry = try #require(history.entries.first)
        #expect(entry.text == "request")
        #expect(entry.status == .failed)
        #expect(entry.error == "Mac unreachable")
    }

    @Test("a send accepted by the Mac follows its job: queued, then sent")
    func acceptedSendFollowsItsJob() throws {
        var history = SendHistory()
        let id = history.record("request", to: workspace)
        history.accept(id, jobId: "job-1")
        #expect(history.entries.first?.status == .queued)

        history.follow([job("job-1", .sending)])
        #expect(history.entries.first?.status == .queued)

        history.follow([job("job-1", .sent)])
        #expect(history.entries.first?.status == .sent)
    }

    @Test("a job failed on the Mac fails the send with its reason")
    func failedJobFailsTheSend() throws {
        var history = SendHistory()
        let id = history.record("request", to: workspace)
        history.accept(id, jobId: "job-1")

        history.follow([job("job-1", .failed, error: "agent not found")])

        let entry = try #require(history.entries.first)
        #expect(entry.status == .failed)
        #expect(entry.error == "agent not found")
    }

    @Test("a job purged by the Mac leaves the send at its last known status")
    func purgedJobKeepsLastStatus() {
        var history = SendHistory()
        let id = history.record("request", to: workspace)
        history.accept(id, jobId: "job-1")
        history.follow([job("job-1", .sent)])

        history.follow([])

        #expect(history.entries.first?.status == .sent)
    }

    @Test("the job of another send does not change the status of this one")
    func otherJobsAreIgnored() {
        var history = SendHistory()
        let id = history.record("request", to: workspace)
        history.accept(id, jobId: "job-1")

        history.follow([job("job-2", .failed, error: "other")])

        #expect(history.entries.first?.status == .queued)
    }

    @Test("a send the -main answers moves from tasks to questions, with its answer")
    func answeredSendBecomesAQuestion() throws {
        var history = SendHistory()
        let id = history.record("how does the cache work?", to: workspace)
        history.accept(id, jobId: "job-1")
        _ = history.record("fix the cache", to: workspace)

        history.receive(Answer(summary: "Cleared on deploy.", body: "Details."), forJob: "job-1")

        #expect(history.tasks.map(\.text) == ["fix the cache"])
        #expect(history.questions.map(\.text) == ["how does the cache work?"])
        #expect(history.questions.first?.answer?.summary == "Cleared on deploy.")
    }

    @Test("only the last 20 questions are kept, without making room at the expense of tasks")
    func keepsOnlyTheTwentyLatestQuestions() {
        var history = SendHistory()
        _ = history.record("task", to: workspace)
        for index in 1...25 {
            let id = history.record("question \(index)", to: workspace)
            history.accept(id, jobId: "job-\(index)")
            history.receive(Answer(summary: "answer \(index)", body: ""), forJob: "job-\(index)")
        }

        #expect(history.questions.count == 20)
        #expect(history.questions.first?.text == "question 25")
        #expect(history.questions.last?.text == "question 6")
        #expect(history.tasks.map(\.text) == ["task"])
    }

    @Test("only answered sends not fetched yet are to be asked from the Mac")
    func answersToFetch() {
        var history = SendHistory()
        for jobId in ["job-1", "job-2", "job-3"] {
            history.accept(history.record(jobId, to: workspace), jobId: jobId)
        }
        history.receive(Answer(summary: "already here", body: ""), forJob: "job-1")
        var answered = [job("job-1", .sent), job("job-2", .sent), job("job-3", .sent), job("job-relay", .sent)]
        for index in [0, 1, 3] { answered[index].answered = true }

        #expect(history.jobsAwaitingAnswer(in: answered) == ["job-2"])
    }

    private func job(_ id: String, _ state: DispatchJob.State, error: String? = nil) -> DispatchJob {
        DispatchJob(id: id, workspaceId: "w1", agent: "heraldr-main", state: state, error: error)
    }
}
