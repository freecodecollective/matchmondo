import Foundation

@MainActor
final class DataService: ObservableObject {
    @Published var matches: [Match] = []
    @Published var players: [String: [Player]] = [:]
    @Published var rosters: [String: [RosterPlayer]] = [:]
    @Published var isLoading = true
    @Published var lastUpdated: Date?

    private let jsonURL = URL(string: "https://raw.githubusercontent.com/freecodecollective/world-cup-2026/main/data/matches.json")!

    func load() async {
        isLoading = true
        do {
            let (data, _) = try await URLSession.shared.data(from: jsonURL)
            let decoded = try JSONDecoder().decode([Match].self, from: data)
            matches = decoded.sorted { $0.kickoff < $1.kickoff }
            lastUpdated = Date()
        } catch {
            print("Failed to load matches: \(error)")
        }
        isLoading = false
    }

    func refresh() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: jsonURL)
            let decoded = try JSONDecoder().decode([Match].self, from: data)
            matches = decoded.sorted { $0.kickoff < $1.kickoff }
            lastUpdated = Date()
        } catch {
            print("Refresh failed: \(error)")
        }
    }

    // Group standings computed from match scores
    func standings() -> [String: [GroupStanding]] {
        var groups: [String: [String: GroupStanding]] = [:]

        for m in matches {
            guard let group = m.group, group.hasPrefix("Group ") else { continue }
            if groups[group] == nil { groups[group] = [:] }

            for team in [m.home, m.away] {
                if TeamFlags.isRealTeam(team) && groups[group]?[team] == nil {
                    groups[group]?[team] = GroupStanding(team: team)
                }
            }

            if let sh = m.scoreH, let sa = m.scoreA,
               groups[group]?[m.home] != nil, groups[group]?[m.away] != nil {
                groups[group]?[m.home]?.played += 1
                groups[group]?[m.away]?.played += 1
                groups[group]?[m.home]?.goalsFor += sh
                groups[group]?[m.home]?.goalsAgainst += sa
                groups[group]?[m.away]?.goalsFor += sa
                groups[group]?[m.away]?.goalsAgainst += sh

                if sh > sa {
                    groups[group]?[m.home]?.won += 1
                    groups[group]?[m.away]?.lost += 1
                    groups[group]?[m.home]?.points += 3
                } else if sh < sa {
                    groups[group]?[m.away]?.won += 1
                    groups[group]?[m.home]?.lost += 1
                    groups[group]?[m.away]?.points += 3
                } else {
                    groups[group]?[m.home]?.drawn += 1
                    groups[group]?[m.away]?.drawn += 1
                    groups[group]?[m.home]?.points += 1
                    groups[group]?[m.away]?.points += 1
                }
            }
        }

        var result: [String: [GroupStanding]] = [:]
        for (group, teamMap) in groups {
            result[group] = teamMap.values.sorted {
                if $0.points != $1.points { return $0.points > $1.points }
                if $0.goalDifference != $1.goalDifference { return $0.goalDifference > $1.goalDifference }
                if $0.goalsFor != $1.goalsFor { return $0.goalsFor > $1.goalsFor }
                return $0.team < $1.team
            }
        }
        return result
    }

    // Matches grouped by day in user's local timezone
    func matchesByDay() -> [(date: Date, dayString: String, matches: [Match])] {
        let cal = Calendar.current
        var grouped: [DateComponents: [Match]] = [:]

        for m in matches {
            let comps = cal.dateComponents([.year, .month, .day], from: m.kickoff)
            grouped[comps, default: []].append(m)
        }

        return grouped.map { (comps, matches) in
            let date = cal.date(from: comps) ?? Date.distantPast
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
            return (date: date, dayString: formatter.string(from: date), matches: matches.sorted { $0.kickoff < $1.kickoff })
        }.sorted { $0.date < $1.date }
    }

    func todayMatches() -> [Match] {
        let cal = Calendar.current
        return matches.filter { cal.isDateInToday($0.kickoff) }
    }

    func tomorrowMatches() -> [Match] {
        let cal = Calendar.current
        return matches.filter { cal.isDateInTomorrow($0.kickoff) }
    }

    var playedCount: Int { matches.filter(\.hasScore).count }
    var totalCount: Int { matches.count }
}
