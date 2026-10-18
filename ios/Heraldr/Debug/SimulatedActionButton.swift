#if DEBUG
    import Foundation

    @MainActor
    enum SimulatedActionButton {
        static let darwinNotification = "com.skelz0r.heraldr.debug.action-button"

        private static weak var model: AppModel?

        static func listen(for model: AppModel) {
            self.model = model
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), nil,
                { _, _, _, _, _ in
                    Task { @MainActor in SimulatedActionButton.model?.dictateToHome() }
                },
                darwinNotification as CFString, nil, .deliverImmediately)
        }
    }
#endif
