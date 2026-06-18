import SwiftUI

struct PlayerDetailView: View {
    let player: Player
    let team: String
    @EnvironmentObject var data: DataService

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)
    private let darkGreen = Color(red: 0.027, green: 0.322, blue: 0.231)

    private var age: Int? {
        data.rosters[team]?.first { $0.name == player.name }?.age
    }

    private var wcGoals: Int {
        data.matchDetails.values.flatMap(\.events).filter {
            ($0.type == .goal || $0.type == .penaltyGoal) && $0.playerName == player.name
        }.count
    }

    private var wcAssists: Int {
        data.matchDetails.values.flatMap(\.events).filter {
            $0.assistName == player.name
        }.count
    }

    private var wcAppearances: Int {
        let teamMatches = data.matches.filter {
            ($0.home == team || $0.away == team) && $0.hasScore
        }
        return teamMatches.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                VStack(spacing: 16) {
                    bioCard
                    wcStatsCard
                }
                .padding(16)
            }
        }
        .background(Color(red: 0.91, green: 0.94, blue: 0.91))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [darkGreen, green],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                let stripeWidth: CGFloat = 46
                var x: CGFloat = 0
                var even = true
                while x < size.width {
                    if even {
                        let rect = CGRect(x: x, y: 0, width: stripeWidth, height: size.height)
                        context.fill(Path(rect), with: .color(.white.opacity(0.06)))
                    }
                    x += stripeWidth
                    even.toggle()
                }
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    if let num = player.number {
                        Text("\(num)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(.white.opacity(0.15))
                                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 2))
                            )
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        HStack(spacing: 0) {
                            Text(player.position)
                            if let age {
                                Text(" \u{00b7} ")
                                Text("Age \(age)")
                            }
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.75))
                        HStack(spacing: 5) {
                            FlagView(team: team, size: 16)
                            Text(TeamNames.localizedName(for: team))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }

                HStack(spacing: 5) {
                    Image(systemName: "building.2")
                        .font(.system(size: 11))
                    Text(player.club)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 12)
        }
        .frame(height: 160)
        .clipped()
    }

    // MARK: - Bio

    private var bioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(green)
                Text("About")
                    .font(.system(size: 14, weight: .bold))
            }
            Text(player.localizedWhy)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - 2026 World Cup Stats

    private var wcStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(green)
                Text("2026 World Cup")
                    .font(.system(size: 14, weight: .bold))
            }

            HStack(spacing: 0) {
                statBox(value: "\(wcAppearances)", label: "Apps")
                statBox(value: "\(wcGoals)", label: "Goals")
                statBox(value: "\(wcAssists)", label: "Assists")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func statBox(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(green)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 2)
    }
}
