import SwiftUI

@main
struct MatchMondoApp: App {
    @StateObject private var dataService = DataService()
    @StateObject private var scoreVisibility = ScoreVisibility()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataService)
                .environmentObject(scoreVisibility)
                .task {
                    await dataService.load()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                scoreVisibility.hideAll()
            }
        }
    }
}
