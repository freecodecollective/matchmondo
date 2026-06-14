import SwiftUI

struct TeamsView: View {
    @EnvironmentObject var data: DataService
    @EnvironmentObject var appSettings: AppSettings
    @State private var searchText = ""
    @State private var expandedTeam: String?

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
            .navigationDestination(for: Match.self) { match in
                MatchDetailView(match: match)
            }
        }
    }

    // MARK: - Team Section

    private func teamSection(team: String) -> some View {
        let isExpanded = expandedTeam == team

        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedTeam = isExpanded ? nil : team
                }
            } label: {
                HStack(spacing: 8) {
                    FlagView(team: team, size: 28)
                    Text(team)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    RankBadge(team: team)
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
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(gold)
                .frame(height: 2)

            if isExpanded {
                teamStats(team: team)
                scheduleSection(team: team)
                playersSection(team: team)
                rosterLink(team: team)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Team Stats

    private func teamStats(team: String) -> some View {
        let teamMatches = data.teamMatches(for: team)
        let gamesPlayed = teamMatches.filter(\.hasScore).count
        let goalsScored = teamMatches.reduce(0) { total, m in
            guard m.hasScore else { return total }
            return total + (m.home == team ? m.scoreH! : m.scoreA!)
        }
        let goalsConceded = teamMatches.reduce(0) { total, m in
            guard m.hasScore else { return total }
            return total + (m.home == team ? m.scoreA! : m.scoreH!)
        }

        return HStack(spacing: 16) {
            statPill(label: "Played", value: "\(gamesPlayed)")
            statPill(label: "GF", value: "\(goalsScored)")
            statPill(label: "GA", value: "\(goalsConceded)")
            if appSettings.showFIFARankings, let rank = Rankings.rank(for: team) {
                statPill(label: "FIFA", value: "#\(rank)")
            }
            if let roster = data.rosters[team] {
                statPill(label: "Squad", value: "\(roster.count)")
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(green.opacity(0.04))
    }

    // MARK: - Schedule

    private func scheduleSection(team: String) -> some View {
        let teamMatches = data.teamMatches(for: team).sorted { $0.kickoff < $1.kickoff }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(green)
                Text("Schedule")
                    .font(.system(size: 13, weight: .bold))
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ForEach(teamMatches) { match in
                NavigationLink(value: match) {
                    scheduleRow(match: match, team: team)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func scheduleRow(match: Match, team: String) -> some View {
        let opponent = match.home == team ? match.away : match.home
        let isHome = match.home == team
        let result = matchResult(match: match, team: team)

        return HStack(spacing: 8) {
            Text(matchDateShort(match.kickoff))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            if match.isLive {
                LiveBadge(detail: nil)
                    .frame(width: 14)
            } else if let result {
                Text(result.letter)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(result.color)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Text("–")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    )
            }

            FlagView(team: opponent, size: 18)

            Text("\(isHome ? "vs" : "at") \(opponent)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if match.hasScore {
                Text("\(match.scoreH!)–\(match.scoreA!)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(match.isLive ? green : .primary)
            } else {
                Text(match.kickoff.smartTime())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - Players

    private func playersSection(team: String) -> some View {
        let players = data.players[team] ?? []
        guard !players.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Divider().padding(.leading, 14)

                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(green)
                    Text("Key Players")
                        .font(.system(size: 13, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    playerCard(player: player)
                    if index < players.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        )
    }

    private func playerCard(player: Player) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let num = player.number {
                    Text("\(num)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(green)
                        .clipShape(Circle())
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.name)
                        .font(.system(size: 15, weight: .bold))
                    Text(player.position)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 4) {
                Image(systemName: "building.2")
                    .font(.system(size: 10))
                Text(player.club)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(green)

            Text(player.why)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Roster Link

    private func rosterLink(team: String) -> some View {
        Group {
            if let roster = data.rosters[team], !roster.isEmpty {
                Divider().padding(.leading, 14)

                NavigationLink {
                    RosterView(team: team, roster: roster)
                } label: {
                    HStack {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 12))
                        Text("View full \(roster.count)-player squad")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(green.opacity(0.06))
                }
            }
        }
    }

    // MARK: - Helpers

    private func teamGroup(_ team: String) -> String? {
        data.matches.first(where: {
            ($0.home == team || $0.away == team) && $0.group != nil
        })?.group?.replacingOccurrences(of: "Group ", with: "Grp ")
    }

    private func matchResult(match: Match, team: String) -> (letter: String, color: Color)? {
        guard match.hasScore, !match.isLive else { return nil }
        let scored = match.home == team ? match.scoreH! : match.scoreA!
        let conceded = match.home == team ? match.scoreA! : match.scoreH!
        if scored > conceded { return ("W", .green) }
        if scored < conceded { return ("L", .red) }
        return ("D", .orange)
    }

    private func matchDateShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
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
