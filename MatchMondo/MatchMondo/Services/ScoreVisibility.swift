import Foundation
import Combine

@MainActor
final class ScoreVisibility: ObservableObject {
    @Published var showScores = false

    private var hideTimer: Timer?
    private static let autoHideInterval: TimeInterval = 5 * 60

    func toggle() {
        showScores.toggle()
        if showScores {
            startAutoHide()
        } else {
            cancelAutoHide()
        }
    }

    func hide() {
        showScores = false
        cancelAutoHide()
    }

    private func startAutoHide() {
        cancelAutoHide()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.autoHideInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showScores = false
            }
        }
    }

    private func cancelAutoHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
}
