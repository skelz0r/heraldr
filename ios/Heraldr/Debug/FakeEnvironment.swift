#if DEBUG
    import Foundation
    import UIKit
    import UserNotifications

    extension AppEnvironment {
        static let fakeDefaultsSuite = "com.skelz0r.heraldr.fake-mac"

        static func fake(
            _ scenario: FakeMacScenario, mac: FakeMac? = nil, suiteName: String = fakeDefaultsSuite, relaunching: Bool = false
        ) -> AppEnvironment {
            let mac = mac ?? FakeMac(scenario)
            if !relaunching {
                UserDefaults().removePersistentDomain(forName: suiteName)
            }
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            if scenario.paired ?? true, !relaunching {
                PairedMacStore.save(FakeMac.pairedMac, to: defaults)
            }
            if !relaunching, let entries = scenario.history,
                let history = try? JSONDecoder().decode(SendHistory.self, from: JSONEncoder().encode(["entries": entries]))
            {
                SendHistoryStore.save(history, to: defaults)
            }
            let lexiconFile = URL.temporaryDirectory.appending(path: "\(suiteName)-lexicon.json")
            if !relaunching {
                try? FileManager.default.removeItem(at: lexiconFile)
            }
            let lexiconStore = DictationLexiconStore(fileURL: lexiconFile, defaults: defaults)
            let journalFile = URL.temporaryDirectory.appending(path: "\(suiteName)-dictation-journal.jsonl")
            if !relaunching {
                try? FileManager.default.removeItem(at: journalFile)
            }
            if !relaunching, let language = scenario.dictationLanguage {
                DictationLanguageStore.save(.specific(language), to: defaults)
            }
            if let lexicon = scenario.lexicon {
                lexiconStore.save(lexicon)
            }
            return AppEnvironment(
                defaults: defaults,
                lexiconStore: lexiconStore,
                dictationJournalFile: journalFile,
                transcriptionLocales: {
                    let identifiers = scenario.transcriptionLocales ?? FakeMacScenario.defaultTranscriptionLocales
                    return TranscriptionLocales.sortedByName(identifiers.map(Locale.init(identifier:)))
                },
                connect: { _ in mac },
                pair: { code in
                    let parsed: PairingCode
                    do throws(PairingCode.ParseError) {
                        parsed = try PairingCode(parsing: code)
                    } catch {
                        throw PairingError.invalidCode(error)
                    }
                    guard let bootstrap = parsed.bootstrap else { throw PairingError.configOnlyCode }
                    guard bootstrap.expiresAt > .now else { throw PairingError.expired }
                    return FakeMac.pairedMac
                },
                requestNotifications: { await scheduleNotification(of: scenario) },
                openURL: { _ in false },
                alert: postLocalNotification)
        }

        private static func scheduleNotification(of scenario: FakeMacScenario) async {
            guard let payload = scenario.notification else { return }
            let delay = scenario.notificationDelay ?? 2
            _ = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                Task { await deliverNotification(payload, after: delay) }
            }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }

        private static func deliverNotification(_ payload: [String: FakeNotificationValue], after delay: Double) async {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .authorized else { return }
            var payload = payload
            let content = UNMutableNotificationContent()
            content.title = payload.removeValue(forKey: "title")?.text ?? ""
            content.subtitle = payload.removeValue(forKey: "subtitle")?.text ?? ""
            content.body = payload.removeValue(forKey: "body")?.text ?? ""
            content.userInfo = payload.mapValues(\.userInfoValue)
            if let reply = QuestionReply(userInfo: content.userInfo) {
                await reply.register()
                content.categoryIdentifier = reply.categoryIdentifier
            }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "fake-mac-question-\(UUID().uuidString)", content: content, trigger: trigger))
        }

        static var launch: AppEnvironment {
            guard let scenario = FakeMacScenario.fromLaunch() else { return .live }
            return .fake(scenario)
        }
    }
#endif
