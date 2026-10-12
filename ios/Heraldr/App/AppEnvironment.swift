import Foundation
import UIKit
import UserNotifications

struct AppEnvironment {
    let defaults: UserDefaults
    let lexiconStore: DictationLexiconStore
    let connect: @MainActor (PairedMac) -> (any MacTransport)?
    let pair: @MainActor (String) async throws -> PairedMac
    let requestNotifications: @MainActor () async -> Void
    let openURL: @MainActor (URL) async -> Bool

    static var live: AppEnvironment {
        AppEnvironment(
            defaults: .standard,
            lexiconStore: .standard,
            connect: { mac in
                guard let key = try? DeviceKeyStore.load() else { return nil }
                return MacLink(mac: mac, deviceKey: key, defaults: .standard)
            },
            pair: { code in
                try await PairingCeremony.pair(code: code, deviceKey: try DeviceKeyStore.loadOrCreate())
            },
            requestNotifications: {
                let center = UNUserNotificationCenter.current()
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            },
            openURL: { url in
                await UIApplication.shared.open(url, options: [.universalLinksOnly: true])
            })
    }
}
