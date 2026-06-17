import Foundation

@MainActor
final class DataService: ObservableObject {
    @Published var matches: [Match] = []
    @Published var players: [String: [Player]] = [:]
    @Published var rosters: [String: [RosterPlayer]] = [:]
    @Published var highlights: [String: Highlight] = [:]
    @Published var isLoading = true
    @Published var lastUpdated: Date?

    private let baseURL = "https://raw.githubusercontent.com/freecodecollective/matchmondo/main/data/"
    private let espnAPI = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard"
    private static let espnTeamMap: [String: String] = [
        "South Korea": "Korea Republic", "United States": "USA",
        "Bosnia-Herzegovina": "Bosnia and Herzegovina", "Cape Verde": "Cabo Verde",
        "Ivory Coast": "Côte d'Ivoire", "Iran": "IR Iran",
    ]
    private var refreshTimer: Timer?
    @Published var anyLive = false
    private var espnEventIDs: [Int: String] = [:]
    @Published var matchDetails: [Int: MatchDetail] = [:]

    func load() async {
        isLoading = true
        await fetchMatches()
        await fetchPlayers()
        await fetchRosters()
        await fetchHighlights()
        isLoading = false
        await refreshScoresFromESPN()
        await buildESPNEventIDMap()
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

    private func buildESPNEventIDMap() async {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.timeZone = TimeZone(identifier: "UTC")

        let matchDates = Set(matches.filter(\.hasScore).map { cal.startOfDay(for: $0.kickoff) })
            .union(Set(matches.filter { $0.isLive }.map { cal.startOfDay(for: $0.kickoff) }))
            .union([today, cal.date(byAdding: .day, value: -1, to: today)!, cal.date(byAdding: .day, value: 1, to: today)!])

        for date in matchDates {
            let dateStr = fmt.string(from: date)
            guard let url = URL(string: "\(espnAPI)?dates=\(dateStr)") else { continue }
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 8
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(ESPNResponse.self, from: data)
                for event in response.events {
                    let kickoff = Self.parseESPNDate(event.date)?.timeIntervalSince1970 ?? 0
                    if let idx = matches.firstIndex(where: { abs($0.kickoff.timeIntervalSince1970 - kickoff) < 120 }) {
                        espnEventIDs[matches[idx].n] = event.id
                    }
                }
            } catch {
                continue
            }
        }
    }

    private func refreshScoresFromESPN() async {
        // Query yesterday/today/tomorrow UTC to catch matches ESPN groups on adjacent days
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.timeZone = TimeZone(identifier: "UTC")

        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let dateStrings = [yesterday, now, tomorrow].map { fmt.string(from: $0) }

        var allEvents: [ESPNEvent] = []
        var seenIDs = Set<String>()
        var anySuccess = false

        for dateStr in dateStrings {
            guard let url = URL(string: "\(espnAPI)?dates=\(dateStr)") else { continue }
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 8
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(ESPNResponse.self, from: data)
                anySuccess = true
                for event in response.events where !seenIDs.contains(event.id) {
                    seenIDs.insert(event.id)
                    allEvents.append(event)
                }
            } catch {
                continue
            }
        }

        guard anySuccess else {
            print("ESPN refresh failed: all date queries failed")
            await fetchMatches()
            return
        }

        var changed = false
        var liveNow = false

        for event in allEvents {
            guard let comp = event.competitions.first else { continue }
            let statusName = comp.status.type.name
            let statusDetail = comp.status.type.shortDetail

            guard let home = comp.competitors.first(where: { $0.homeAway == "home" }),
                  let away = comp.competitors.first(where: { $0.homeAway == "away" }) else { continue }

            let kickoff = Self.parseESPNDate(event.date)?.timeIntervalSince1970 ?? 0
            guard let idx = matches.firstIndex(where: {
                abs($0.kickoff.timeIntervalSince1970 - kickoff) < 120
            }) else { continue }

            espnEventIDs[matches[idx].n] = event.id

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

    func standings(includeLive: Bool = false) -> [String: [GroupStanding]] {
        var groups: [String: [String: GroupStanding]] = [:]

        for m in matches {
            guard let group = m.group, group.hasPrefix("Group ") else { continue }
            if groups[group] == nil { groups[group] = [:] }

            for team in [m.home, m.away] {
                if TeamFlags.isRealTeam(team) && groups[group]?[team] == nil {
                    groups[group]?[team] = GroupStanding(team: team)
                }
            }

            if let sh = m.scoreH, let sa = m.scoreA, (includeLive || !m.isLive),
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

    func yesterdayMatches() -> [Match] {
        let cal = Calendar.current
        return matches.filter { cal.isDateInYesterday($0.kickoff) }
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

    func fetchMatchDetail(for match: Match) async {
        guard (matchDetails[match.n] == nil || match.isLive),
              let eventID = espnEventIDs[match.n],
              let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/summary?event=\(eventID)")
        else { return }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            let summary = try JSONDecoder().decode(ESPNSummary.self, from: data)

            var events: [MatchEvent] = []

            for ke in summary.keyEvents {
                let typeName = ke.type.text
                let minute = ke.clock?.displayValue ?? ""
                let teamName = ke.team?.displayName ?? ""
                let participants = ke.participants ?? []

                let eventType: MatchEventType?
                let typeKey = ke.type.type
                switch typeKey {
                case "own-goal":
                    eventType = .ownGoal
                case "penalty-scored", "penalty---scored":
                    eventType = .penaltyGoal
                case _ where typeKey == "goal" || typeKey.hasPrefix("goal---"):
                    if typeName.lowercased().contains("own goal") {
                        eventType = .ownGoal
                    } else {
                        eventType = .goal
                    }
                case "yellow-card":
                    eventType = .yellowCard
                case "red-card":
                    if typeName.lowercased().contains("second yellow") {
                        eventType = .secondYellow
                    } else {
                        eventType = .redCard
                    }
                case "substitution":
                    eventType = .substitution
                default:
                    eventType = nil
                }

                guard let type = eventType else { continue }

                let playerName = participants.first?.athlete.displayName ?? ""
                var assistName: String? = nil
                var playerOut: String? = nil

                if type == .goal || type == .penaltyGoal || type == .ownGoal {
                    if participants.count > 1 {
                        assistName = participants[1].athlete.displayName
                    }
                } else if type == .substitution {
                    if participants.count > 1 {
                        playerOut = participants[1].athlete.displayName
                    }
                }

                events.append(MatchEvent(
                    minute: minute,
                    type: type,
                    teamName: teamName,
                    playerName: playerName,
                    assistName: assistName,
                    playerOut: playerOut,
                    description: ke.text ?? ""
                ))
            }

            let boxscore = summary.boxscore
            func parseStats(_ teamData: ESPNBoxscoreTeam?) -> TeamStats? {
                guard let t = teamData else { return nil }
                let map = Dictionary(uniqueKeysWithValues: t.statistics.map { ($0.label, $0.displayValue) })
                return TeamStats(
                    teamName: t.team.displayName,
                    possession: map["Possession"],
                    shots: map["SHOTS"],
                    shotsOnGoal: map["ON GOAL"],
                    corners: map["Corner Kicks"],
                    fouls: map["Fouls"],
                    yellowCards: map["Yellow Cards"],
                    redCards: map["Red Cards"],
                    offsides: map["Offsides"],
                    saves: map["Saves"],
                    passAccuracy: map["Pass Completion %"]
                )
            }

            let homeTeam = boxscore?.teams.first
            let awayTeam: ESPNBoxscoreTeam? = (boxscore?.teams.count ?? 0) > 1 ? boxscore?.teams[1] : nil

            let detail = MatchDetail(
                events: events,
                homeStats: parseStats(homeTeam),
                awayStats: parseStats(awayTeam),
                attendance: summary.gameInfo?.attendance,
                referee: summary.gameInfo?.officials?.first?.fullName
            )

            matchDetails[match.n] = detail
        } catch {
            print("Failed to fetch match detail: \(error)")
        }
    }
}

// MARK: - ESPN API Models

private struct ESPNResponse: Decodable {
    let events: [ESPNEvent]
}

private struct ESPNEvent: Decodable {
    let id: String
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

// MARK: - ESPN Summary Models

private struct ESPNSummary: Decodable {
    let keyEvents: [ESPNKeyEvent]
    let boxscore: ESPNBoxscore?
    let gameInfo: ESPNGameInfo?
}

private struct ESPNKeyEvent: Decodable {
    let type: ESPNEventType
    let text: String?
    let clock: ESPNClock?
    let team: ESPNTeamRef?
    let participants: [ESPNParticipant]?
}

private struct ESPNEventType: Decodable {
    let text: String
    let type: String
}

private struct ESPNClock: Decodable {
    let displayValue: String
}

private struct ESPNTeamRef: Decodable {
    let displayName: String
}

private struct ESPNParticipant: Decodable {
    let athlete: ESPNAthlete
}

private struct ESPNAthlete: Decodable {
    let displayName: String
}

private struct ESPNBoxscore: Decodable {
    let teams: [ESPNBoxscoreTeam]
}

private struct ESPNBoxscoreTeam: Decodable {
    let team: ESPNTeamRef
    let statistics: [ESPNStatistic]
}

private struct ESPNStatistic: Decodable {
    let label: String
    let displayValue: String
}

private struct ESPNGameInfo: Decodable {
    let attendance: Int?
    let officials: [ESPNOfficial]?
}

private struct ESPNOfficial: Decodable {
    let fullName: String
}
