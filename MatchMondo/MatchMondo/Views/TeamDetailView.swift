import SwiftUI

struct TeamDetailView: View {
    let team: String
    @EnvironmentObject var data: DataService
    @EnvironmentObject var appSettings: AppSettings

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)
    private let gold = Color(red: 0.91, green: 0.725, blue: 0.137)

    private var teamMatches: [Match] {
        data.teamMatches(for: team).sorted { $0.kickoff < $1.kickoff }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerCard
                statsCard
                scheduleCard
                playersCard
                rosterCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(red: 0.91, green: 0.94, blue: 0.91))
        .navigationTitle(team)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Match.self) { match in
            MatchDetailView(match: match)
        }
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            FlagView(team: team, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(team)
                    .font(.system(size: 22, weight: .bold))
                HStack(spacing: 8) {
                    RankBadge(team: team)
                    if let group = teamGroup {
                        NavigationLink {
                            StandingsDetailView(scrollToGroup: group)
                        } label: {
                            HStack(spacing: 4) {
                                Text(group)
                                    .font(.system(size: 12, weight: .semibold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private var statsCard: some View {
        let played = teamMatches.filter(\.hasScore).count
        let gf = teamMatches.reduce(0) { t, m in
            guard m.hasScore else { return t }
            return t + (m.home == team ? m.scoreH! : m.scoreA!)
        }
        let ga = teamMatches.reduce(0) { t, m in
            guard m.hasScore else { return t }
            return t + (m.home == team ? m.scoreA! : m.scoreH!)
        }
        let wins = teamMatches.filter { m in
            guard m.hasScore else { return false }
            let scored = m.home == team ? m.scoreH! : m.scoreA!
            let conceded = m.home == team ? m.scoreA! : m.scoreH!
            return scored > conceded
        }.count
        let draws = teamMatches.filter { m in
            guard m.hasScore else { return false }
            return (m.home == team ? m.scoreH! : m.scoreA!) == (m.home == team ? m.scoreA! : m.scoreH!)
        }.count
        let losses = played - wins - draws

        return HStack(spacing: 16) {
            statPill(label: "Played", value: "\(played)")
            statPill(label: "W", value: "\(wins)")
            statPill(label: "D", value: "\(draws)")
            statPill(label: "L", value: "\(losses)")
            statPill(label: "GF", value: "\(gf)")
            statPill(label: "GA", value: "\(ga)")
            if let roster = data.rosters[team] {
                statPill(label: "Squad", value: "\(roster.count)")
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(green)
                Text("Schedule")
                    .font(.system(size: 14, weight: .bold))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(teamMatches) { match in
                NavigationLink(value: match) {
                    scheduleRow(match: match)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func scheduleRow(match: Match) -> some View {
        let opponent = match.home == team ? match.away : match.home
        let isHome = match.home == team
        let result = matchResult(match: match)

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

    @ViewBuilder
    private var playersCard: some View {
        let players = data.players[team] ?? []
        if !players.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(green)
                    Text("Key Players")
                        .font(.system(size: 14, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    playerRow(player: player)
                    if index < players.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func playerRow(player: Player) -> some View {
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

    @ViewBuilder
    private var rosterCard: some View {
        if let roster = data.rosters[team], !roster.isEmpty {
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
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Helpers

    private var teamGroup: String? {
        data.matches.first(where: {
            ($0.home == team || $0.away == team) && $0.group != nil
        })?.group
    }

    private func matchResult(match: Match) -> (letter: String, color: Color)? {
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
