import Foundation

struct Target: Equatable, Sendable {
    let workspace: Workspace
    let tab: Tab?

    init(_ workspace: Workspace, tab: Tab? = nil) {
        self.workspace = workspace
        self.tab = tab
    }

    var id: String { tab?.id ?? workspace.id }

    var tabName: String { tab?.displayName ?? Tab.mainName }

    var label: String { "\(workspace.label) — \(tabName)" }
}
