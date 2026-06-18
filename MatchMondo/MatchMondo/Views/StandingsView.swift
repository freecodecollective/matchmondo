import SwiftUI

struct StandingsView: View {
    @EnvironmentObject var data: DataService
    @State private var includeLive = false

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)
    private let gold = Color(red: 0.91, green: 0.725, blue: 0.137)

    var body: some View {
        NavigationStack {
            ScrollView {

                ElectricHeaderBanner(style: .compact)

                if data.isLoading {
                    ProgressView("Loading...")
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            chip("Exclude in-progress", isOn: !includeLive) { includeLive = false }
                            chip("Include in-progress", isOn: includeLive) { includeLive = true }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        Text("Top 2 advance + 8 best third-placed teams")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        legendRow
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)

                        let standings = data.standings(includeLive: includeLive)
                        let sortedGroups = standings.keys.sorted()

                        ForEach(sortedGroups, id: \.self) { group in
                            groupCard(group: group, teams: standings[group] ?? [])
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .background(Color(red: 0.91, green: 0.94, blue: 0.91))
            .navigationTitle("Standings")
            .toolbarBackground(Color(red: 0.02, green: 0.082, blue: 0.067), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: String.self) { team in
                TeamDetailView(team: team)
            }
            .refreshable {
                await data.refresh()
            }
        }
    }

    private var legendRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(green.opacity(0.2)).frame(width: 10, height: 10)
                Text("Advances (top 2)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Circle().fill(gold.opacity(0.3)).frame(width: 10, height: 10)
                Text("Best-third contender")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func groupCard(group: String, teams: [GroupStanding]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(group)
                    .font(.system(size: 16, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.91, green: 0.725, blue: 0.137).opacity(0.15))

            // Header
            HStack(spacing: 0) {
                Text("#").frame(width: 24).font(.system(size: 11, weight: .semibold))
                Text("Team").font(.system(size: 11, weight: .semibold))
                Spacer()
                Group {
                    Text("P").frame(width: 26)
                    Text("W").frame(width: 26)
                    Text("D").frame(width: 26)
                    Text("L").frame(width: 26)
                    Text("GD").frame(width: 30)
                    Text("Pts").frame(width: 30)
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider()

            ForEach(Array(teams.enumerated()), id: \.element.id) { index, standing in
                standingRow(position: index + 1, standing: standing)
                if index < teams.count - 1 {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func chip(_ label: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void) -> some View {
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

    private func standingRow(position: Int, standing: GroupStanding) -> some View {
        let bgColor: Color = position <= 2
            ? green.opacity(0.06)
            : position == 3 ? gold.opacity(0.06) : .clear

        return NavigationLink(value: standing.team) {
            HStack(spacing: 0) {
                Text("\(position)")
                    .frame(width: 24)
                    .font(.system(size: 12, weight: position <= 2 ? .bold : .regular))
                    .foregroundStyle(position <= 2 ? green : position == 3 ? gold : .secondary)

                HStack(spacing: 6) {
                    FlagView(team: standing.team, size: 20)
                    HStack(spacing: 2) {
                        Text(TeamNames.localizedName(for: standing.team))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        RankBadge(team: standing.team, fontSize: 10)
                    }
                }

                Spacer()

                Group {
                    Text("\(standing.played)").frame(width: 26)
                    Text("\(standing.won)").frame(width: 26)
                    Text("\(standing.drawn)").frame(width: 26)
                    Text("\(standing.lost)").frame(width: 26)
                    Text(standing.goalDifference > 0 ? "+\(standing.goalDifference)" : "\(standing.goalDifference)")
                        .frame(width: 30)
                    Text("\(standing.points)")
                        .frame(width: 30)
                        .fontWeight(.heavy)
                }
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(bgColor)
        }
        .buttonStyle(.plain)
    }
}

struct StandingsDetailView: View {
    let scrollToGroup: String
    @EnvironmentObject var data: DataService
    @EnvironmentObject var appSettings: AppSettings

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)
    private let gold = Color(red: 0.91, green: 0.725, blue: 0.137)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 4) {
                    let standings = data.standings(includeLive: false)
                    let sortedGroups = standings.keys.sorted()

                    ForEach(sortedGroups, id: \.self) { group in
                        groupCard(group: group, teams: standings[group] ?? [])
                            .id(group)
                    }
                }
                .padding(.bottom, 20)
                .padding(.top, 8)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        proxy.scrollTo(scrollToGroup, anchor: .top)
                    }
                }
            }
        }
        .background(Color(red: 0.91, green: 0.94, blue: 0.91))
        .navigationTitle("Standings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { team in
            TeamDetailView(team: team)
        }
    }

    private func groupCard(group: String, teams: [GroupStanding]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(group)
                    .font(.system(size: 16, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(gold.opacity(0.15))

            HStack(spacing: 0) {
                Text("#").frame(width: 24).font(.system(size: 11, weight: .semibold))
                Text("Team").font(.system(size: 11, weight: .semibold))
                Spacer()
                Group {
                    Text("P").frame(width: 26)
                    Text("W").frame(width: 26)
                    Text("D").frame(width: 26)
                    Text("L").frame(width: 26)
                    Text("GD").frame(width: 30)
                    Text("Pts").frame(width: 30)
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider()

            ForEach(Array(teams.enumerated()), id: \.element.id) { index, standing in
                standingRow(position: index + 1, standing: standing)
                if index < teams.count - 1 {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func standingRow(position: Int, standing: GroupStanding) -> some View {
        let bgColor: Color = position <= 2
            ? green.opacity(0.06)
            : position == 3 ? gold.opacity(0.06) : .clear

        return NavigationLink(value: standing.team) {
            HStack(spacing: 0) {
                Text("\(position)")
                    .frame(width: 24)
                    .font(.system(size: 12, weight: position <= 2 ? .bold : .regular))
                    .foregroundStyle(position <= 2 ? green : position == 3 ? gold : .secondary)

                HStack(spacing: 6) {
                    FlagView(team: standing.team, size: 20)
                    HStack(spacing: 2) {
                        Text(TeamNames.localizedName(for: standing.team))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        RankBadge(team: standing.team, fontSize: 10)
                    }
                }

                Spacer()

                Group {
                    Text("\(standing.played)").frame(width: 26)
                    Text("\(standing.won)").frame(width: 26)
                    Text("\(standing.drawn)").frame(width: 26)
                    Text("\(standing.lost)").frame(width: 26)
                    Text(standing.goalDifference > 0 ? "+\(standing.goalDifference)" : "\(standing.goalDifference)")
                        .frame(width: 30)
                    Text("\(standing.points)")
                        .frame(width: 30)
                        .fontWeight(.heavy)
                }
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(bgColor)
        }
        .buttonStyle(.plain)
    }
}
