import Foundation

@MainActor
final class DataService: ObservableObject {
    @Published var matches: [Match] = []
    @Published var players: [String: [Player]] = [:]
    @Published var rosters: [String: [RosterPlayer]] = [:]
    @Published var highlights: [String: Highlight] = [:]
    @Published var isLoading = true
    @Published var lastUpdated: Date?

    private let baseURL = "https://raw.githubusercontent.com/freecodecollective/world-cup-2026/main/data/"
    private let espnAPI = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard"
    private static let espnTeamMap: [String: String] = [
        "South Korea": "Korea Republic", "United States": "USA",
        "Bosnia-Herzegovina": "Bosnia and Herzegovina", "Cape Verde": "Cabo Verde",
        "Ivory Coast": "Côte d'Ivoire", "Iran": "IR Iran",
    ]
    private var refreshTimer: Timer?
    @Published var anyLive = false

    func load() async {
        isLoading = true
        await fetchMatches()
        await fetchPlayers()
        await fetchRosters()
        await fetchHighlights()
        isLoading = false
        await refreshScoresFromESPN()
        startAutoRefresh()
    }

    func refresh() async {
        await refreshScoresFromESPN()
    }

    private func fetchMatches() async {
        guard let url = cacheBustedURL("matches.json") else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode([Match].self, from: data)
            matches = decoded.sorted { $0.kickoff < $1.kickoff }
            lastUpdated = Date()
        } catch {
            print("Failed to load matches: \(error)")
        }
    }

    private func fetchPlayers() async {
        guard let url = cacheBustedURL("players.js") else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            guard var text = String(data: data, encoding: .utf8) else { return }
            if let eqRange = text.range(of: "= ") {
                text = String(text[eqRange.upperBound...])
            }
            if text.hasSuffix(";\n") || text.hasSuffix(";") {
                text = String(text.dropLast(text.hasSuffix(";\n") ? 2 : 1))
            }
            let jsonData = Data(text.utf8)
            let response = try JSONDecoder().decode(PlayersResponse.self, from: jsonData)
            players = response.teams
        } catch {
            print("Failed to load players: \(error)")
        }
    }

    private func fetchRosters() async {
        guard let url = cacheBustedURL("rosters.js") else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            guard var text = String(data: data, encoding: .utf8) else { return }
            if let eqRange = text.range(of: "= ") {
                text = String(text[eqRange.upperBound...])
            }
            if text.hasSuffix(";\n") || text.hasSuffix(";") {
                text = String(text.dropLast(text.hasSuffix(";\n") ? 2 : 1))
            }
            let jsonData = Data(text.utf8)
            rosters = try JSONDecoder().decode([String: [RosterPlayer]].self, from: jsonData)
        } catch {
            print("Failed to load rosters: \(error)")
        }
    }

    private func fetchHighlights() async {
        guard let url = cacheBustedURL("highlights.json") else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            highlights = try JSONDecoder().decode([String: Highlight].self, from: data)
        } catch {
            print("Failed to load highlights: \(error)")
        }
    }

    func highlight(for matchNumber: Int) -> Highlight? {
        highlights[String(matchNumber)]
    }

    private func cacheBustedURL(_ file: String) -> URL? {
        let ts = Int(Date().timeIntervalSince1970)
        return URL(string: "\(baseURL)\(file)?t=\(ts)")
    }

    private func refreshScoresFromESPN() async {
        guard let url = URL(string: espnAPI) else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ESPNResponse.self, from: data)

            var changed = false
            var liveNow = false

            for event in response.events {
                guard let comp = event.competitions.first else { continue }
                let statusName = comp.status.type.name
                let statusDetail = comp.status.type.shortDetail

                guard let home = comp.competitors.first(where: { $0.homeAway == "home" }),
                      let away = comp.competitors.first(where: { $0.homeAway == "away" }) else { continue }

                let kickoff = Self.parseESPNDate(event.date)?.timeIntervalSince1970 ?? 0
                guard let idx = matches.firstIndex(where: {
                    abs($0.kickoff.timeIntervalSince1970 - kickoff) < 120
                }) else { continue }

                let isLive = statusName.contains("IN_PROGRESS") || statusName.contains("HALF")
                    || statusName.contains("EXTRA") || statusName.contains("PENALT")
                let isFinished = statusName == "STATUS_FULL_TIME"
                if isLive { liveNow = true }

                var newH: Int? = nil
                var newA: Int? = nil
                if isLive || isFinished {
                    newH = Int(home.score ?? "")
                    newA = Int(away.score ?? "")
                }

                let newDetail: String? = isLive ? statusDetail : nil
                if matches[idx].scoreH != newH || matches[idx].scoreA != newA
                    || matches[idx].isLive != isLive || matches[idx].liveDetail != newDetail {
                    matches[idx].scoreH = newH
                    matches[idx].scoreA = newA
                    matches[idx].isLive = isLive
                    matches[idx].liveDetail = newDetail
                    changed = true
                }
            }

            anyLive = liveNow
            if changed { lastUpdated = Date() }
            await fetchHighlights()
        } catch {
            print("ESPN refresh failed: \(error)")
            await fetchMatches()
        }
    }

    private func startAutoRefresh() {
        scheduleNextRefresh()
    }

    private func scheduleNextRefresh() {
        refreshTimer?.invalidate()
        let interval: TimeInterval = anyLive ? 30 : 60
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshScoresFromESPN()
                self.scheduleNextRefresh()
            }
        }
    }

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

    func teamMatches(for team: String) -> [Match] {
        matches.filter { $0.home == team || $0.away == team }
    }

    var playedCount: Int { matches.filter(\.hasScore).count }
    var totalCount: Int { matches.count }

    private static func parseESPNDate(_ str: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        if let d = fmt.date(from: str) { return d }
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: str) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.date(from: str)
    }
}

// MARK: - ESPN API Models

private struct ESPNResponse: Decodable {
    let events: [ESPNEvent]
}

private struct ESPNEvent: Decodable {
    let date: String
    let competitions: [ESPNCompetition]
}

private struct ESPNCompetition: Decodable {
    let competitors: [ESPNCompetitor]
    let status: ESPNStatus
}

private struct ESPNCompetitor: Decodable {
    let homeAway: String
    let score: String?
}

private struct ESPNStatus: Decodable {
    let type: ESPNStatusType
}

private struct ESPNStatusType: Decodable {
    let name: String
    let shortDetail: String
}
