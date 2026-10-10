import SwiftUI

extension Color {
    static let heraldrAccent = Color("AccentColor")
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x04241D)
    static let recording = Color(light: 0xD70015, dark: 0xFF453A)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
        })
    }

    static let wallBase = Color(light: 0xEEF3F1, dark: 0x050607)
    static let wallBlobOne = Color(light: 0xA8EBD9, dark: 0x0E3B32)
    static let wallBlobTwo = Color(light: 0xC9D6F2, dark: 0x151A2C)
    static let wallBlobThree = Color(light: 0x9FE0F0, dark: 0x0B2A33)
}

extension AgentStatus {
    var color: Color {
        switch self {
        case .idle, .unknown: Color(light: 0x6B7075, dark: 0x8E9399)
        case .working: Color(light: 0x005FCC, dark: 0x4DA3FF)
        case .blocked: Color(light: 0xA84F00, dark: 0xFF9F0A)
        case .done: Color(light: 0x3F8A12, dark: 0x8BD450)
        }
    }

    var label: String {
        switch self {
        case .idle: "Inactif"
        case .working: "Travaille"
        case .blocked: "Attend une réponse"
        case .done: "Terminé"
        case .unknown: "État inconnu"
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

    var nextSend: String {
        switch self {
        case .missing: "Un envoi lancera Claude dans le tab 1."
        case .sending: "Un nouvel envoi partira juste après."
        case .agent(.idle, _), .agent(.done, _): "Un envoi vide son contexte puis transmet la demande."
        case .agent(.working, _): "Un nouvel envoi attendra la fin de son travail."
        case .agent(.blocked, _): "Un nouvel envoi attendra que tu lui aies répondu."
        case .agent(.unknown, _): "Un nouvel envoi attendra qu'il soit prêt."
        }
    }
}
