import SwiftUI

@main
struct HeraldrApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if model.mac == nil {
                    PairingView()
                } else {
                    HomeView()
                }
            }
            .environment(model)
            .tint(.heraldrAccent)
            .task {
                model.resetTargetToHome()
                await model.refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: Task { await model.refresh() }
                case .background: model.pause()
                default: break
                }
            }
        }
    }
}
