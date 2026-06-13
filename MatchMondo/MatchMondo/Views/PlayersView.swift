import SwiftUI

struct PlayersView: View {
    @EnvironmentObject var data: DataService
    @State private var searchText = ""

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)

    private var allTeams: [String] {
        let teams = Set(data.matches.flatMap { [$0.home, $0.away] })
            .filter { TeamFlags.isRealTeam($0) }
        return teams.sorted {
            let ra = Rankings.rank(for: $0) ?? 999
            let rb = Rankings.rank(for: $1) ?? 999
            if ra != rb { return ra < rb }
            return $0 < $1
        }
    }

    private var filteredTeams: [String] {
        if searchText.isEmpty { return allTeams }
        return allTeams.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if data.isLoading {
                    ProgressView("Loading...")
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        Text("Top players to watch on every team, ordered by FIFA ranking.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                        LazyVStack(spacing: 16) {
                            ForEach(filteredTeams, id: \.self) { team in
                                teamSection(team: team)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
            .background(Color(red: 0.91, green: 0.94, blue: 0.91))
            .navigationTitle("Players")
            .searchable(text: $searchText, prompt: "Search teams...")
        }
    }

    private func teamSection(team: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FlagView(team: team, size: 28)
                Text(team)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                RankBadge(team: team)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(red: 0.91, green: 0.725, blue: 0.137))
                    .frame(height: 3)
            }

            // Show a set of notable players for this team
            let teamMatches = data.matches.filter { $0.home == team || $0.away == team }
            let gamesPlayed = teamMatches.filter(\.hasScore).count
            let goalsScored = teamMatches.reduce(0) { total, m in
                guard m.hasScore else { return total }
                return total + (m.home == team ? m.scoreH! : m.scoreA!)
            }

            HStack(spacing: 16) {
                statPill(label: "Matches", value: "\(gamesPlayed)")
                statPill(label: "Goals", value: "\(goalsScored)")
                if let rank = Rankings.rank(for: team) {
                    statPill(label: "FIFA Rank", value: "#\(rank)")
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
            .overlay(
                UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(green)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
}
