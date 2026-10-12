import UIKit
import UserNotifications

struct PushDevice: Sendable, Equatable {
    let token: String
    let environment: String
    let topic: String
    let teamId: String

    init?(token: Data, bundle: Bundle = .main) {
        guard
            let topic = bundle.bundleIdentifier,
            let teamId = bundle.object(forInfoDictionaryKey: "HeraldrTeamID") as? String
        else { return nil }
        self.token = token.map { String(format: "%02x", $0) }.joined()
        self.topic = topic
        self.teamId = teamId
        #if DEBUG
        environment = "sandbox"
        #else
        environment = "production"
        #endif
    }
}

struct QuestionNotification: Sendable, Equatable {
    let workspaceId: String
    let agent: String
    let sessionURL: URL?

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let workspaceId = userInfo["workspace_id"] as? String,
            let agent = userInfo["agent"] as? String
        else { return nil }
        self.workspaceId = workspaceId
        self.agent = agent
        sessionURL = (userInfo["session_url"] as? String).flatMap(URL.init(string:))
    }
}

struct AnswerNotification: Sendable, Equatable {
    let jobId: String
    let workspaceId: String
    let summary: String

    init?(userInfo: [AnyHashable: Any]) {
        guard
            userInfo["kind"] as? String == "answer",
            let jobId = userInfo["job_id"] as? String,
            let workspaceId = userInfo["workspace_id"] as? String
        else { return nil }
        self.jobId = jobId
        self.workspaceId = workspaceId
        let alert = (userInfo["aps"] as? [String: Any])?["alert"] as? [String: Any]
        summary = alert?["body"] as? String ?? ""
    }
}

enum NotificationTap: Sendable, Equatable {
    case question(QuestionNotification)
    case answer(AnswerNotification)

    init?(userInfo: [AnyHashable: Any]) {
        if let answer = AnswerNotification(userInfo: userInfo) {
            self = .answer(answer)
        } else if let question = QuestionNotification(userInfo: userInfo) {
            self = .question(question)
        } else {
            return nil
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: AppModel? {
        didSet { deliverPending() }
    }

    private var pendingDevice: PushDevice?
    private var pendingTap: NotificationTap?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pendingDevice = PushDevice(token: deviceToken)
        deliverPending()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        model?.notice = AppModel.Notice(kind: .failed, title: "Notifications indisponibles", detail: error.localizedDescription)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let tap = NotificationTap(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in
            if let tap { received(tap) }
            completionHandler()
        }
    }

    private func received(_ tap: NotificationTap) {
        pendingTap = tap
        deliverPending()
    }

    private func deliverPending() {
        guard let model else { return }
        if let device = pendingDevice {
            pendingDevice = nil
            Task { await model.registerPush(device) }
        }
        if let tap = pendingTap {
            pendingTap = nil
            switch tap {
            case .question(let question): Task { await model.open(question) }
            case .answer(let answer): Task { await model.open(answer) }
            }
        }
    }
}
