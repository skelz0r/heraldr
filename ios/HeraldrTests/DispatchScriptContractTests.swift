import Foundation
import Testing
@testable import Heraldr

@Suite("Contrat entre l'app et dispatch.sh")
struct DispatchScriptContractTests {
    @Test("les lignes de dispatch.sh status deviennent les envois affichés par l'app")
    func statusLines() {
        let jobs = DispatchJob.parse(statusOutput: """
            20261010120000-41-ab12cd34\tw1\thome-main\tqueued\t
            20261010120100-42-ef56ab78\tw5\tvideo-studio-main\tfailed\tl'agent video-studio-main appartient au workspace w9

            """)

        #expect(jobs == [
            DispatchJob(id: "20261010120000-41-ab12cd34", workspaceId: "w1", agent: "home-main", state: .queued, error: nil),
            DispatchJob(id: "20261010120100-42-ef56ab78", workspaceId: "w5", agent: "video-studio-main", state: .failed, error: "l'agent video-studio-main appartient au workspace w9"),
        ])
        #expect(jobs.map(\.isPending) == [true, false])
    }

    @Test("un état inconnu d'un script plus récent est ignoré sans masquer les autres envois")
    func unknownState() {
        let jobs = DispatchJob.parse(statusOutput: "a\tw1\thome-main\tcancelled\t\nb\tw1\thome-main\tsending\t\n")

        #expect(jobs.map(\.id) == ["b"])
    }

    @Test("sans script installé sur le Mac, aucun envoi n'est listé")
    func noScript() {
        #expect(DispatchJob.parse(statusOutput: "").isEmpty)
    }

    @Test("le relais de Home enveloppe la demande exactement comme l'app le fait pour un projet")
    func relayEnvelopeMatchesApp() throws {
        let script = String(decoding: Dispatcher.bundledScript, as: UTF8.self)
        let heredoc = try #require(script.firstMatch(of: #/standard_envelope\(\) \{\n  cat <<EOF\n(?<body>.*?)\nEOF\n/#.dotMatchesNewlines()))
        let project = Workspace(id: "w5", number: 5, label: "Video studio")

        #expect(PromptEnvelope.wrap("Ajoute un sous-titre", for: project) == heredoc.body.replacingOccurrences(of: "$1", with: "Ajoute un sous-titre"))
    }

    @Test("Home, quel que soit son label, reçoit la consigne qui relaie au projet ; un projet ne la reçoit jamais")
    func homeEnvelope() {
        let home = Workspace(id: "wA", number: 1, label: "Home")
        let project = Workspace(id: "w5", number: 5, label: "Video studio")

        #expect(PromptEnvelope.wrap("x", for: home).contains("dispatch.sh\" relay"))
        #expect(!PromptEnvelope.wrap("x", for: project).contains("relay"))
    }

    @Test("un envoi vers un tab prévient d'une dictée possible, sans consigne ni /start")
    func tabEnvelope() {
        #expect(PromptEnvelope.forTab("  Le bouton est trop petit\n") == """
            Demande envoyée depuis l'iPhone (peut venir d'une dictée vocale : attention aux erreurs de transcription).

            Le bouton est trop petit
            """)
    }
}
