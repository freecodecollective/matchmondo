import Foundation
import Combine

@MainActor
final class ScoreVisibility: ObservableObject {
    @Published var showCompleted = false
    @Published var showLive = false

    private var hideTimer: Timer?
    private static let autoHideInterval: TimeInterval = 5 * 60

    func shouldShowScore(for match: Match) -> Bool {
        if match.isLive { return showLive }
        if match.hasScore { return showCompleted }
        return false
    }

    func toggleCompleted() {
        showCompleted.toggle()
        if showCompleted { startAutoHide() } else if !showLive { cancelAutoHide() }
    }

    func toggleLive() {
        showLive.toggle()
        if showLive { startAutoHide() } else if !showCompleted { cancelAutoHide() }
    }

    func hideAll() {
        showCompleted = false
        showLive = false
        cancelAutoHide()
    }

    var isHideAll: Bool { !showCompleted && !showLive }

    private func startAutoHide() {
        cancelAutoHide()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.autoHideInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showCompleted = false
                self?.showLive = false
            }
        }
    }

    private func cancelAutoHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
}
