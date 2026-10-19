import UserNotifications

struct QuestionReply: Sendable, Equatable {
    struct Option: Sendable, Equatable {
        let number: Int
        let label: String

        var actionIdentifier: String { QuestionReply.actionPrefix + String(number) }
    }

    static let actionPrefix = "option."
    static let categoryPrefix = "question."
    static let maximumOptions = 4

    let paneId: String
    let questionId: String
    let options: [Option]

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let paneId = userInfo["pane_id"] as? String,
            let questionId = userInfo["question_id"] as? String,
            let entries = userInfo["options"] as? [[String: Any]]
        else { return nil }
        let options = entries.compactMap { entry -> Option? in
            guard let number = entry["number"] as? Int, (1...9).contains(number), let label = entry["label"] as? String, !label.isEmpty
            else { return nil }
            return Option(number: number, label: label)
        }
        guard !options.isEmpty, options.count == entries.count, options.count <= Self.maximumOptions else { return nil }
        self.paneId = paneId
        self.questionId = questionId
        self.options = options
    }

    var categoryIdentifier: String { Self.categoryPrefix + questionId }

    var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: options.map { UNNotificationAction(identifier: $0.actionIdentifier, title: $0.label, options: [.authenticationRequired]) },
            intentIdentifiers: [])
    }

    func option(forAction identifier: String) -> Option? {
        options.first { $0.actionIdentifier == identifier }
    }

    func register() async {
        await QuestionCategories.shared.add(self)
    }
}

actor QuestionCategories {
    static let shared = QuestionCategories()
    private static let keptRecent = 8

    private var recent: [String] = []
    private var tail: Task<Void, Never>?

    func add(_ question: QuestionReply) async {
        let previous = tail
        let recent = Array((recent + [question.categoryIdentifier]).suffix(Self.keptRecent))
        self.recent = recent
        let update = Task {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            let shown = await center.deliveredNotifications().map(\.request.content.categoryIdentifier)
            let kept = Set(shown + recent)
            let categories = await center.notificationCategories().filter {
                !$0.identifier.hasPrefix(QuestionReply.categoryPrefix) || kept.contains($0.identifier)
            }
            center.setNotificationCategories(categories.union([question.category]))
            _ = await center.notificationCategories()
        }
        tail = update
        await update.value
    }
}
