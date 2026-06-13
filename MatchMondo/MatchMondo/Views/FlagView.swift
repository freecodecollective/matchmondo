import SwiftUI

struct FlagView: View {
    let team: String
    var size: CGFloat = 22

    var body: some View {
        if let url = TeamFlags.flagURL(for: team) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size * 0.72)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                        )
                default:
                    flagPlaceholder
                }
            }
        } else {
            flagPlaceholder
        }
    }

    private var flagPlaceholder: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.gray.opacity(0.15))
            .frame(width: size, height: size * 0.72)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
    }
}

struct RankBadge: View {
    let team: String

    var body: some View {
        if let rank = Rankings.rank(for: team) {
            Text("#\(rank)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.043, green: 0.431, blue: 0.310))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color(red: 0.043, green: 0.431, blue: 0.310).opacity(0.1))
                .clipShape(Capsule())
        }
    }
}

struct TeamNameView: View {
    let team: String
    var isWinner: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            FlagView(team: team)
            Text(team)
                .font(.system(size: 15, weight: isWinner ? .heavy : .semibold))
                .foregroundStyle(isWinner ? Color(red: 0.027, green: 0.322, blue: 0.231) : .primary)
        }
    }
}
