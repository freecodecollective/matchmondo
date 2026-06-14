import Foundation
import Combine

enum ScoreMode: Equatable {
    case hideAll
    case completedOnly
    case all
}

@MainActor
final class ScoreVisibility: ObservableObject {
    @Published var mode: ScoreMode = .hideAll

    private var hideTimer: Timer?
    private static let autoHideInterval: TimeInterval = 5 * 60

    var showScores: Bool { mode != .hideAll }

    func shouldShowScore(for match: Match) -> Bool {
        switch mode {
        case .hideAll: return false
        case .completedOnly: return match.hasScore && !match.isLive
        case .all: return true
        }
    }

    func setMode(_ newMode: ScoreMode) {
        mode = newMode
        if newMode != .hideAll {
            startAutoHide()
        } else {
            cancelAutoHide()
        }
    }

    func hide() {
        mode = .hideAll
        cancelAutoHide()
    }

    private func startAutoHide() {
        cancelAutoHide()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.autoHideInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.mode = .hideAll
            }
        }
    }

    private func cancelAutoHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
}
