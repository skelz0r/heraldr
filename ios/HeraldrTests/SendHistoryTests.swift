import Foundation
import Testing
@testable import Heraldr

@Suite("Historique des envois")
struct SendHistoryTests {
    private let workspace = Workspace(id: "w1", number: 2, label: "heraldr", agentStatus: .idle)

    @Test("on ne garde que les 20 derniers envois, du plus récent au plus ancien")
    func keepsOnlyTheTwentyLatestSends() {
        var history = SendHistory()
        for index in 1...25 {
            _ = history.record("envoi \(index)", to: workspace)
        }

        #expect(history.entries.count == 20)
        #expect(history.entries.first?.text == "envoi 25")
        #expect(history.entries.last?.text == "envoi 6")
    }

    @Test("un envoi encore en cours quand l'app est relancée garde son texte, marqué interrompu")
    func interruptedSendSurvivesRelaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: "send-history-\(UUID())"))
        var history = SendHistory()
        _ = history.record("texte à ne pas perdre", to: workspace)
        SendHistoryStore.save(history, to: defaults)

        let relaunched = SendHistoryStore.load(from: defaults)

        let entry = try #require(relaunched.entries.first)
        #expect(entry.text == "texte à ne pas perdre")
        #expect(entry.workspaceId == "w1")
        #expect(entry.status == .failed)
        #expect(entry.error == SendHistory.interruptedError)
    }

    @Test("un envoi refusé avant d'atteindre le Mac garde son texte et la raison de l'échec")
    func localFailureKeepsText() throws {
        var history = SendHistory()
        let id = history.record("demande", to: workspace)

        history.fail(id, error: "Mac injoignable")

        let entry = try #require(history.entries.first)
        #expect(entry.text == "demande")
        #expect(entry.status == .failed)
        #expect(entry.error == "Mac injoignable")
    }

    @Test("un envoi accepté par le Mac suit son job : en file, puis envoyé")
    func acceptedSendFollowsItsJob() throws {
        var history = SendHistory()
        let id = history.record("demande", to: workspace)
        history.accept(id, jobId: "job-1")
        #expect(history.entries.first?.status == .queued)

        history.follow([job("job-1", .sending)])
        #expect(history.entries.first?.status == .queued)

        history.follow([job("job-1", .sent)])
        #expect(history.entries.first?.status == .sent)
    }

    @Test("un job passé en échec sur le Mac met l'envoi en échec avec sa raison")
    func failedJobFailsTheSend() throws {
        var history = SendHistory()
        let id = history.record("demande", to: workspace)
        history.accept(id, jobId: "job-1")

        history.follow([job("job-1", .failed, error: "agent introuvable")])

        let entry = try #require(history.entries.first)
        #expect(entry.status == .failed)
        #expect(entry.error == "agent introuvable")
    }

    @Test("un job purgé par le Mac laisse l'envoi à son dernier statut connu")
    func purgedJobKeepsLastStatus() {
        var history = SendHistory()
        let id = history.record("demande", to: workspace)
        history.accept(id, jobId: "job-1")
        history.follow([job("job-1", .sent)])

        history.follow([])

        #expect(history.entries.first?.status == .sent)
    }

    @Test("le job d'un autre envoi ne change pas le statut de celui-ci")
    func otherJobsAreIgnored() {
        var history = SendHistory()
        let id = history.record("demande", to: workspace)
        history.accept(id, jobId: "job-1")

        history.follow([job("job-2", .failed, error: "autre")])

        #expect(history.entries.first?.status == .queued)
    }

    private func job(_ id: String, _ state: DispatchJob.State, error: String? = nil) -> DispatchJob {
        DispatchJob(id: id, workspaceId: "w1", agent: "heraldr-main", state: state, error: error)
    }
}
