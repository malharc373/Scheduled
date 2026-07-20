import SwiftUI

/// iOS entry point. Shares the entire Core pipeline (AppState, OpenRouterClient,
/// EventKitManager, DayPlanner, RoutineStore, Keychain) with the macOS app.
@main
struct SchedulediOSApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            CaptureScreen(state: state)
        }
    }
}
