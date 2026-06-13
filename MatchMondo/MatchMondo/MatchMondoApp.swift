import SwiftUI

@main
struct MatchMondoApp: App {
    @StateObject private var dataService = DataService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataService)
                .task {
                    await dataService.load()
                }
        }
    }
}
