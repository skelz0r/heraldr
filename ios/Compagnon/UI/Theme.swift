import SwiftUI

extension Color {
    static let compagnonAccent = Color("AccentColor")

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

    static let wallBase = Color(light: 0xEEF0F6, dark: 0x06070B)
    static let wallBlobOne = Color(light: 0xFFB98A, dark: 0x7A2C6A)
    static let wallBlobTwo = Color(light: 0xB9A4FF, dark: 0x2B2F9E)
    static let wallBlobThree = Color(light: 0x8FE3D0, dark: 0x0D6E66)
}

extension AgentStatus {
    var color: Color {
        switch self {
        case .idle, .unknown: Color(light: 0x8E8E93, dark: 0x8E8E93)
        case .working: Color(light: 0x0A84FF, dark: 0x3B9BFF)
        case .blocked: Color(light: 0xFF9500, dark: 0xFF9F0A)
        case .done: Color(light: 0x28C840, dark: 0x32D74B)
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

    var dispatchHint: String {
        switch self {
        case .idle, .done: "prêt : contexte vidé puis envoi"
        case .working: "l'envoi partira après son travail"
        case .blocked: "attend une réponse : l'envoi patientera"
        case .unknown: "l'envoi partira dès qu'il sera prêt"
        }
    }
}
