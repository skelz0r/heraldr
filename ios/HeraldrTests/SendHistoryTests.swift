import Foundation
import Testing
@testable import Heraldr

@Suite("Historique des envois")
struct SendHistoryTests {
    private let workspace = Workspace(id: "w1", number: 2, label: "heraldr")

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

    @Test("un envoi auquel le -main répond passe des tâches aux questions, avec sa réponse")
    func answeredSendBecomesAQuestion() throws {
        var history = SendHistory()
        let id = history.record("comment marche le cache ?", to: workspace)
        history.accept(id, jobId: "job-1")
        _ = history.record("corrige le cache", to: workspace)

        history.receive(Answer(summary: "Vidé au déploiement.", body: "Détail."), forJob: "job-1")

        #expect(history.tasks.map(\.text) == ["corrige le cache"])
        #expect(history.questions.map(\.text) == ["comment marche le cache ?"])
        #expect(history.questions.first?.answer?.summary == "Vidé au déploiement.")
    }

    @Test("seules les 20 dernières questions sont gardées, sans faire de place aux dépens des tâches")
    func keepsOnlyTheTwentyLatestQuestions() {
        var history = SendHistory()
        _ = history.record("tâche", to: workspace)
        for index in 1...25 {
            let id = history.record("question \(index)", to: workspace)
            history.accept(id, jobId: "job-\(index)")
            history.receive(Answer(summary: "réponse \(index)", body: ""), forJob: "job-\(index)")
        }

        #expect(history.questions.count == 20)
        #expect(history.questions.first?.text == "question 25")
        #expect(history.questions.last?.text == "question 6")
        #expect(history.tasks.map(\.text) == ["tâche"])
    }

    @Test("seuls les envois répondus et pas encore récupérés sont à demander au Mac")
    func answersToFetch() {
        var history = SendHistory()
        for jobId in ["job-1", "job-2", "job-3"] {
            history.accept(history.record(jobId, to: workspace), jobId: jobId)
        }
        history.receive(Answer(summary: "déjà là", body: ""), forJob: "job-1")
        var answered = [job("job-1", .sent), job("job-2", .sent), job("job-3", .sent), job("job-relais", .sent)]
        for index in [0, 1, 3] { answered[index].answered = true }

        #expect(history.jobsAwaitingAnswer(in: answered) == ["job-2"])
    }

    private func job(_ id: String, _ state: DispatchJob.State, error: String? = nil) -> DispatchJob {
        DispatchJob(id: id, workspaceId: "w1", agent: "heraldr-main", state: state, error: error)
    }
}
