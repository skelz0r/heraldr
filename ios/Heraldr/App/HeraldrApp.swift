import AppIntents
import SwiftUI

@main
struct HeraldrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel(environment: .launch)
        _model = State(initialValue: model)
        AppDependencyManager.shared.add(dependency: model)
        AppDelegate.launchedModel = model
        #if DEBUG
            SimulatedActionButton.listen(for: model)
        #endif
    }

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
                appDelegate.model = model
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
