import Testing
@testable import Heraldr

@Suite("Nom de l'agent herdr visé dans un workspace")
struct AgentNameTests {
    @Test("le workspace ~ vise home-main")
    func homeWorkspace() {
        #expect(AgentName.forWorkspace(label: "~") == "home-main")
    }

    @Test("un label déjà valide est gardé tel quel")
    func validLabel() {
        #expect(AgentName.forWorkspace(label: "acme_app") == "acme_app-main")
    }

    @Test("majuscules et espaces deviennent minuscules et tirets")
    func labelWithSpacesAndCapitals() {
        #expect(AgentName.forWorkspace(label: "Herdr ios companion") == "herdr-ios-companion-main")
    }

    @Test("un label long est tronqué pour rester un nom d'agent herdr valide")
    func longLabel() {
        let name = AgentName.forWorkspace(label: "Un workspace au nom vraiment beaucoup trop long")

        #expect(name == "un-workspace-au-nom-vraimen-main")
        #expect(name.wholeMatch(of: #/[a-z][a-z0-9_-]{0,31}/#) != nil)
    }
}
