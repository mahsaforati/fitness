import SwiftUI
import SwiftData

@main
struct WorkoutTrackerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(for: SetLog.self)
    }
}
