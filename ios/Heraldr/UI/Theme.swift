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
        self.init(
            uiColor: UIColor { traits in
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
        case .idle: "Idle"
        case .working: "Working"
        case .blocked: "Waiting for an answer"
        case .done: "Done"
        case .unknown: "Not detected"
        }
    }
}

extension SentRequest.Status {
    var color: Color {
        switch self {
        case .sending, .queued: Color(light: 0xFFCC00, dark: 0xFFD60A)
        case .sent: Color(light: 0x248A3D, dark: 0x30D158)
        case .failed: Color(light: 0xD70015, dark: 0xFF453A)
        }
    }

    var label: String {
        switch self {
        case .sending: "Sending…"
        case .queued: "Queued"
        case .sent: "Sent"
        case .failed: "Failed"
        }
    }
}

extension AppModel.TargetState {
    var headline: String {
        switch self {
        case .missing: "No agent yet"
        case .ambiguousMain: "Several -main Claudes"
        case .tabWithoutClaude: "No Claude left in this tab"
        case .sending: "Sending…"
        case .agent(.idle, _), .agent(.done, _): "Ready"
        case .agent(.working, true): "Working on your request"
        case .agent(.working, false): "Working"
        case .agent(.blocked, _): "Asking you a question: answer in Claude mobile"
        case .agent(.unknown, _): "Unknown state"
        }
    }

    func nextSend(to target: Target, clearingContext: Bool = false) -> String {
        switch self {
        case .missing: "A send will start Claude in tab 1, named \(AgentName.forWorkspace(label: target.workspace.label))."
        case .ambiguousMain(let names):
            "A send will fail: keep only one of \(names.joined(separator: ", ")), or name it \(AgentName.forWorkspace(label: target.workspace.label))."
        case .tabWithoutClaude: "A send will fail: restart Claude in this tab on the Mac."
        case .sending: "A new send will go out right after."
        case .agent(.idle, _), .agent(.done, _):
            target.tab == nil || clearingContext
                ? "A send clears its context, then hands over the request."
                : "A send hands over the request as is, keeping its context."
        case .agent(.working, _): "A new send will wait until it finishes its work."
        case .agent(.blocked, _): "A new send will wait until you have answered it."
        case .agent(.unknown, _): "A new send will wait until it is ready."
        }
    }
}
