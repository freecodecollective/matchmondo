import SwiftUI

struct TeamsView: View {
    @EnvironmentObject var data: DataService
    @EnvironmentObject var appSettings: AppSettings
    @State private var searchText = ""

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)
    private let gold = Color(red: 0.91, green: 0.725, blue: 0.137)

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
        return allTeams.filter { team in
            team.localizedCaseInsensitiveContains(searchText) ||
            (data.players[team] ?? []).contains { p in
                p.name.localizedCaseInsensitiveContains(searchText) ||
                p.club.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if data.isLoading {
                    ProgressView("Loading...")
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        Text(appSettings.showFIFARankings
                            ? "All 48 teams, ordered by FIFA ranking."
                            : "All 48 teams competing in the 2026 World Cup.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                        LazyVStack(spacing: 12) {
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
            .navigationTitle("Teams")
            .searchable(text: $searchText, prompt: "Search teams or players...")
            .navigationDestination(for: String.self) { team in
                TeamDetailView(team: team)
            }
        }
    }

    // MARK: - Team Section

    private func teamSection(team: String) -> some View {
        NavigationLink(value: team) {
            HStack(spacing: 8) {
                FlagView(team: team, size: 28)
                HStack(spacing: 4) {
                    Text(team)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    RankBadge(team: team)
                }
                Spacer()
                if let group = teamGroup(team) {
                    Text(group)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func teamGroup(_ team: String) -> String? {
        data.matches.first(where: {
            ($0.home == team || $0.away == team) && $0.group != nil
        })?.group?.replacingOccurrences(of: "Group ", with: "Grp ")
    }
}

struct RosterView: View {
    let team: String
    let roster: [RosterPlayer]

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)

    private var grouped: [(position: String, players: [RosterPlayer])] {
        let order = ["GK", "DF", "MF", "FW"]
        let names = ["Goalkeepers", "Defenders", "Midfielders", "Forwards"]
        return order.enumerated().compactMap { i, pos in
            let players = roster.filter { $0.position == pos }.sorted { $0.number < $1.number }
            return players.isEmpty ? nil : (position: names[i], players: players)
        }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.position) { group in
                Section(group.position) {
                    ForEach(group.players) { player in
                        HStack(spacing: 10) {
                            Text("\(player.number)")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(green)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.name)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(player.club)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Age \(player.age)")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(team)
        .navigationBarTitleDisplayMode(.large)
    }
}
