import SwiftUI

struct ScoreFilterBar: View {
    @EnvironmentObject var scoreVisibility: ScoreVisibility

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)

    var body: some View {
        Menu {
            Button {
                scoreVisibility.hideAll()
            } label: {
                HStack {
                    Text("Hide Scores")
                    if scoreVisibility.isHideAll {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                scoreVisibility.showCompleted = true
                scoreVisibility.showLive = false
            } label: {
                HStack {
                    Text("Final Scores")
                    if scoreVisibility.showCompleted && !scoreVisibility.showLive {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                scoreVisibility.showCompleted = true
                scoreVisibility.showLive = true
            } label: {
                HStack {
                    Text("Final & Live Scores")
                    if scoreVisibility.showCompleted && scoreVisibility.showLive {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: scoreVisibility.isHideAll ? "eye.slash" : "eye")
                    .font(.system(size: 13, weight: .semibold))
                Text("Score options")
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(scoreVisibility.isHideAll ? .secondary : green)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(scoreVisibility.isHideAll ? Color(.systemGray5) : green.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(scoreVisibility.isHideAll ? Color.clear : green, lineWidth: 1.5)
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
