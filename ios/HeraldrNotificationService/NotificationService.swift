import UserNotifications
import os

final class NotificationService: UNNotificationServiceExtension {
    private var delivery: Delivery?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let reply = QuestionReply(userInfo: request.content.userInfo)
        let content = request.content.mutableCopy() as? UNMutableNotificationContent
        if let reply, let content {
            content.categoryIdentifier = reply.categoryIdentifier
        }
        let delivery = Delivery(content ?? request.content, to: contentHandler)
        self.delivery = delivery
        guard let reply else {
            delivery.deliver()
            return
        }
        Task {
            await reply.register()
            delivery.deliver()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        delivery?.deliver()
    }
}

private final class Delivery: Sendable {
    private let pending: OSAllocatedUnfairLock<(() -> Void)?>

    init(_ content: UNNotificationContent, to handler: @escaping (UNNotificationContent) -> Void) {
        pending = OSAllocatedUnfairLock(uncheckedState: { handler(content) })
    }

    func deliver() {
        let delivering = pending.withLockUnchecked { pending in
            defer { pending = nil }
            return pending
        }
        delivering?()
    }
}
