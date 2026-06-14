import SwiftUI

struct ScoreFilterBar: View {
    @EnvironmentObject var scoreVisibility: ScoreVisibility

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)

    var body: some View {
        HStack(spacing: 6) {
            chip("Hide all scores", isOn: scoreVisibility.isHideAll) {
                scoreVisibility.hideAll()
            }
            chip("Completed", isOn: scoreVisibility.showCompleted) {
                scoreVisibility.toggleCompleted()
            }
            chip("Live", isOn: scoreVisibility.showLive) {
                scoreVisibility.toggleLive()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func chip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? .white : .primary)
                .background(isOn ? green : Color(.systemGray5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
