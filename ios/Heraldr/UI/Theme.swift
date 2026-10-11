import SwiftUI

extension Color {
    static let heraldrAccent = Color("AccentColor")
    static let onAccent = Color.white
    static let onStatus = Color(light: 0xFFFFFF, dark: 0x121214)
    static let macOnline = Color(light: 0x1F8A4C, dark: 0x6EDB8F)

    static let selectedGlass = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.92, darkOpacity: 0.2)
    static let restingGlass = Color(light: 0x8A8D96, dark: 0x000000, lightOpacity: 0.12, darkOpacity: 0)
    static let selectedGlow = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.1, darkOpacity: 0.1)
    static let voiceInk = Color(light: 0xC2321A, dark: 0xFF7A5C)
    static let voiceGlow = Color(light: 0xFF5A3C, dark: 0xFF5A3C)

    init(light: UInt32, dark: UInt32, lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let hex = isDark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: isDark ? darkOpacity : lightOpacity)
        })
    }

    static let wallBase = Color(light: 0xF1F1F3, dark: 0x0B0B0D)
    static let wallBlobOne = Color(light: 0xD8DAE0, dark: 0x26282E)
    static let wallBlobTwo = Color(light: 0xE4E7EE, dark: 0x1A1D24)
    static let wallBlobThree = Color(light: 0xF4D3CB, dark: 0x3A1712)
}

extension AgentStatus {
    var color: Color {
        switch self {
        case .unknown: Color(light: 0x6A6C73, dark: 0xD7D8DD)
        case .idle, .done: Color(light: 0x1F8A4C, dark: 0x6EDB8F)
        case .working: Color(light: 0x0A63C9, dark: 0x64C8FF)
        case .blocked: Color(light: 0x8F5400, dark: 0xFFC23D)
        }
    }

    var isHollow: Bool {
        self == .unknown
    }

    var label: String {
        switch self {
        case .idle: "Inactif"
        case .working: "Travaille"
        case .blocked: "Attend une réponse"
        case .done: "Terminé"
        case .unknown: "Non détecté"
        }
    }
}

extension AppModel.TargetState {
    var headline: String {
        switch self {
        case .missing: "Pas encore d'agent"
        case .sending: "Envoi en cours…"
        case .agent(.idle, _), .agent(.done, _): "Prêt"
        case .agent(.working, true): "Travaille sur ta demande"
        case .agent(.working, false): "Travaille"
        case .agent(.blocked, _): "Te pose une question : réponds dans Claude mobile"
        case .agent(.unknown, _): "État inconnu"
        }
    }

    func nextSend(to workspace: Workspace) -> String {
        switch self {
        case .missing: "Un envoi lancera Claude dans le tab 1, nommé \(AgentName.forWorkspace(label: workspace.label))."
        case .sending: "Un nouvel envoi partira juste après."
        case .agent(.idle, _), .agent(.done, _): "Un envoi vide son contexte puis transmet la demande."
        case .agent(.working, _): "Un nouvel envoi attendra la fin de son travail."
        case .agent(.blocked, _): "Un nouvel envoi attendra que tu lui aies répondu."
        case .agent(.unknown, _): "Un nouvel envoi attendra qu'il soit prêt."
        }
    }
}
