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
    let reply: QuestionReply?

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let workspaceId = userInfo["workspace_id"] as? String,
            let agent = userInfo["agent"] as? String
        else { return nil }
        self.workspaceId = workspaceId
        self.agent = agent
        sessionURL = (userInfo["session_url"] as? String).flatMap(URL.init(string:))
        reply = QuestionReply(userInfo: userInfo)
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
    static weak var launchedModel: AppModel?

    weak var model: AppModel? {
        didSet { deliverPending() }
    }

    private var pendingDevice: PushDevice?
    private var pendingTap: NotificationTap?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if model == nil {
            model = Self.launchedModel
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pendingDevice = PushDevice(token: deviceToken)
        deliverPending()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        model?.notice = AppModel.Notice(kind: .failed, title: "Notifications unavailable", detail: error.localizedDescription)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let tap = NotificationTap(userInfo: response.notification.request.content.userInfo)
        let action = response.actionIdentifier
        Task { @MainActor in
            if case .question(let question) = tap, let option = question.reply?.option(forAction: action) {
                await answer(question, with: option)
            } else if let tap {
                received(tap)
            }
            completionHandler()
        }
    }

    private func answer(_ question: QuestionNotification, with option: QuestionReply.Option) async {
        guard let model = model ?? Self.launchedModel else { return }
        let backgroundTask = BackgroundTask(named: "Answer \(question.agent)")
        await model.answer(question, with: option)
        backgroundTask.end()
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

@MainActor
private final class BackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(named name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
