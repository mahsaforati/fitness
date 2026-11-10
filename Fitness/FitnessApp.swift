import SwiftUI
import SwiftData

@main
struct FitnessApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(for: SetLog.self)
    }
}
