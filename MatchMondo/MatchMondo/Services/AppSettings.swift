import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("showWorldRankings") var showWorldRankings = true
    @AppStorage("showMatchLocations") var showMatchLocations = true
    @AppStorage("showCountryFlags") var showCountryFlags = true
    @AppStorage("showGameTimes") var showGameTimes = true
    @AppStorage("launchCount") private(set) var launchCount = 0
    @AppStorage("reviewDismissedForever") var reviewDismissedForever = false
    @AppStorage("reviewSnoozedUntil") var reviewSnoozedUntil: Double = 0
    @Published var showReviewPrompt = false

    func recordLaunch() {
        launchCount += 1
    }

    func checkForReviewPrompt() {
        guard launchCount >= 10, !reviewDismissedForever else { return }
        if reviewSnoozedUntil > 0 && Date().timeIntervalSince1970 < reviewSnoozedUntil { return }
        showReviewPrompt = true
    }

    func openAppStoreReview() {
        reviewDismissedForever = true
        showReviewPrompt = false
        if let url = URL(string: "https://apps.apple.com/app/id6780063871?action=write-review") {
            UIApplication.shared.open(url)
        }
    }

    func snoozeReview() {
        showReviewPrompt = false
        reviewSnoozedUntil = Date().addingTimeInterval(2 * 24 * 60 * 60).timeIntervalSince1970
    }

    func dismissReviewForever() {
        reviewDismissedForever = true
        showReviewPrompt = false
    }
}
