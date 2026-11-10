import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "figure.strengthtraining.traditional") }
            Text("Calendar — next commit").tabItem { Label("Calendar", systemImage: "calendar") }
            Text("Progress — next commit").tabItem { Label("Progress", systemImage: "chart.bar") }
            PlanView().tabItem { Label("Plan", systemImage: "list.bullet.rectangle") }
        }
        .tint(Color(white: 0.15))
    }
}
