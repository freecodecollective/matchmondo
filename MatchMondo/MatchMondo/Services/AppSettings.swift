import SwiftUI
import StoreKit

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("showFIFARankings") var showFIFARankings = true
    @AppStorage("launchCount") private(set) var launchCount = 0
    @AppStorage("reviewDismissedForever") var reviewDismissedForever = false
    @AppStorage("reviewSnoozedUntil") var reviewSnoozedUntil: Double = 0
    @Published var showReviewPrompt = false

    func recordLaunch() {
        launchCount += 1
    }

    func checkForReviewPrompt() {
        guard launchCount >= 5, !reviewDismissedForever else { return }
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
