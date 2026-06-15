import SwiftUI

struct ScoreFilterBar: View {
    @EnvironmentObject var scoreVisibility: ScoreVisibility

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)

    private var scoresOn: Bool {
        scoreVisibility.showCompleted || scoreVisibility.showLive
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if scoresOn {
                    scoreVisibility.hideAll()
                } else {
                    scoreVisibility.showCompleted = true
                }
            } label: {
                Image(systemName: scoresOn ? "eye" : "eye.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(scoresOn ? .white : .secondary)
                    .frame(width: 32, height: 32)
                    .background(scoresOn ? green : Color(.systemGray5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            if scoresOn {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1, height: 18)

                chip("Final Scores", icon: "trophy.fill", isOn: scoreVisibility.showCompleted) {
                    scoreVisibility.toggleCompleted()
                }
                chip("Live Scores", icon: "antenna.radiowaves.left.and.right", isOn: scoreVisibility.showLive) {
                    scoreVisibility.toggleLive()
                }
            } else {
                Text("Scores hidden")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: scoresOn)
    }

    private func chip(_ label: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isOn ? green : .secondary)
            .background(isOn ? green.opacity(0.12) : Color(.systemGray5))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isOn ? green : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
