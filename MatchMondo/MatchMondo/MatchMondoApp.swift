import SwiftUI

@main
struct MatchMondoApp: App {
    @StateObject private var dataService = DataService()
    @StateObject private var scoreVisibility = ScoreVisibility()
    @StateObject private var appSettings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataService)
                .environmentObject(scoreVisibility)
                .environmentObject(appSettings)
                .task {
                    await dataService.load()
                    appSettings.recordLaunch()
                    appSettings.checkForReviewPrompt()
                }
                .alert("Enjoying MatchMondo?", isPresented: $appSettings.showReviewPrompt) {
                    Button("Leave a Review") { appSettings.openAppStoreReview() }
                    Button("Ask me later") { appSettings.snoozeReview() }
                    Button("Don't ask again", role: .cancel) { appSettings.dismissReviewForever() }
                } message: {
                    Text("If you like MatchMondo, please spread the love with a quick app review. It would mean a lot to us.")
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                scoreVisibility.hideAll()
            }
        }
    }
}
