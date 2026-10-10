import Foundation
import Testing
@testable import Heraldr

@Suite("Nom de l'agent herdr visé dans un workspace")
struct AgentNameTests {
    @Test("le workspace ~ vise home-main")
    func homeWorkspace() {
        #expect(AgentName.forWorkspace(label: "~") == "home-main")
    }

    @Test("l'app et dispatch.sh relay donnent le même nom d'agent, valide pour herdr", arguments: AgentNameVectors.shared)
    func sharedWithDispatchScript(vector: AgentNameVectors.Vector) {
        let name = AgentName.forWorkspace(label: vector.label)

        #expect(name == vector.agent)
        #expect(name.wholeMatch(of: #/[a-z][a-z0-9_-]{0,31}/#) != nil)
    }
}

enum AgentNameVectors {
    struct Vector: CustomTestStringConvertible, Sendable {
        let label: String
        let agent: String

        var testDescription: String { "\(label) → \(agent)" }
    }

    static let shared: [Vector] = {
        let url = Bundle(for: BundleMarker.self).url(forResource: "agent-names", withExtension: "tsv")!
        return try! String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map { line in
                let fields = line.split(separator: "\t").map(String.init)
                return Vector(label: fields[0], agent: fields[1])
            }
    }()

    private final class BundleMarker {}
}
