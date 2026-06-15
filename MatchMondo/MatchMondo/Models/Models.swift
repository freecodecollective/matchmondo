import Foundation

struct Match: Codable, Identifiable, Hashable {
    var id: Int { n }
    let n: Int
    let utc: String
    let stage: String
    let group: String?
    let home: String
    let away: String
    let venue: String
    let city: String
    let tv: String?
    var scoreH: Int?
    var scoreA: Int?

    var isLive: Bool = false
    var liveDetail: String?

    enum CodingKeys: String, CodingKey {
        case n, utc, stage, group, home, away, venue, city, tv, scoreH, scoreA
    }

    var kickoff: Date {
        ISO8601DateFormatter().date(from: utc) ?? Date.distantPast
    }

    var hasScore: Bool { scoreH != nil && scoreA != nil }

    var stageLabel: String { group ?? stage }

    var stageSlug: String {
        switch stage {
        case "Group Stage": return "group"
        case "Round of 32": return "r32"
        case "Round of 16": return "r16"
        case "Quarter-finals": return "qf"
        case "Semi-finals": return "sf"
        case "Third-place Match": return "third"
        case "Final": return "final"
        default: return "group"
        }
    }
}

struct PlayersResponse: Codable {
    let teams: [String: [Player]]
}

struct Player: Codable, Identifiable {
    var id: String { "\(name)-\(club)" }
    let name: String
    let position: String
    let club: String
    let hometown: String
    let why: String
    let number: Int?
}

struct RosterPlayer: Codable, Identifiable {
    var id: String { "\(name)-\(number)" }
    let name: String
    let number: Int
    let age: Int
    let position: String
    let club: String
}

struct Highlight: Codable {
    let short: String?
    let extended: String?
    let shortDuration: String?
    let extendedDuration: String?
}

struct GroupStanding: Identifiable {
    var id: String { team }
    let team: String
    var played = 0
    var won = 0
    var drawn = 0
    var lost = 0
    var goalsFor = 0
    var goalsAgainst = 0
    var points = 0
    var goalDifference: Int { goalsFor - goalsAgainst }
}

enum TeamFlags {
    static let codes: [String: String] = [
        "Algeria": "dz", "Argentina": "ar", "Australia": "au", "Austria": "at", "Belgium": "be",
        "Bosnia and Herzegovina": "ba", "Brazil": "br", "Cabo Verde": "cv", "Canada": "ca",
        "Colombia": "co", "Congo DR": "cd", "Croatia": "hr", "Curaçao": "cw", "Czechia": "cz",
        "Côte d'Ivoire": "ci", "Ecuador": "ec", "Egypt": "eg", "England": "gb-eng", "France": "fr",
        "Germany": "de", "Ghana": "gh", "Haiti": "ht", "IR Iran": "ir", "Iraq": "iq", "Japan": "jp",
        "Jordan": "jo", "Korea Republic": "kr", "Mexico": "mx", "Morocco": "ma", "Netherlands": "nl",
        "New Zealand": "nz", "Norway": "no", "Panama": "pa", "Paraguay": "py", "Portugal": "pt",
        "Qatar": "qa", "Saudi Arabia": "sa", "Scotland": "gb-sct", "Senegal": "sn", "South Africa": "za",
        "Spain": "es", "Sweden": "se", "Switzerland": "ch", "Tunisia": "tn", "Türkiye": "tr",
        "USA": "us", "Uruguay": "uy", "Uzbekistan": "uz",
    ]

    static func flagURL(for team: String) -> URL? {
        guard let code = codes[team] else { return nil }
        return URL(string: "https://flagcdn.com/w40/\(code).png")
    }

    static func isRealTeam(_ team: String) -> Bool {
        codes[team] != nil
    }
}

enum Rankings {
    static let ranks: [String: Int] = [
        "Argentina": 1, "Spain": 2, "France": 3, "England": 4, "Portugal": 5,
        "Brazil": 6, "Morocco": 7, "Netherlands": 8, "Belgium": 9, "Germany": 10,
        "Croatia": 11, "Colombia": 13, "Mexico": 14, "Senegal": 15, "Uruguay": 16,
        "USA": 17, "Japan": 18, "Switzerland": 19, "IR Iran": 20, "Türkiye": 22,
        "Ecuador": 23, "Austria": 24, "Korea Republic": 25, "Australia": 27, "Algeria": 28,
        "Egypt": 29, "Canada": 30, "Norway": 31, "Côte d'Ivoire": 33, "Panama": 34,
        "Sweden": 38, "Czechia": 40, "Paraguay": 41, "Scotland": 42, "Tunisia": 45,
        "Congo DR": 46, "Uzbekistan": 50, "Qatar": 56, "Iraq": 57, "South Africa": 60,
        "Saudi Arabia": 61, "Jordan": 63, "Bosnia and Herzegovina": 64, "Cabo Verde": 67,
        "Ghana": 73, "Curaçao": 82, "Haiti": 83, "New Zealand": 85,
    ]

    static func rank(for team: String) -> Int? { ranks[team] }
}

// MARK: - Match Detail (from ESPN Summary API)

struct MatchDetail {
    let events: [MatchEvent]
    let homeStats: TeamStats?
    let awayStats: TeamStats?
    let attendance: Int?
    let referee: String?
}

struct MatchEvent: Identifiable {
    let id = UUID()
    let minute: String
    let type: MatchEventType
    let teamName: String
    let playerName: String
    let assistName: String?
    let playerOut: String?
    let description: String
}

enum MatchEventType {
    case goal, penaltyGoal, ownGoal, yellowCard, redCard, secondYellow, substitution
}

struct TeamStats {
    let teamName: String
    let possession: String?
    let shots: String?
    let shotsOnGoal: String?
    let corners: String?
    let fouls: String?
    let yellowCards: String?
    let redCards: String?
    let offsides: String?
    let saves: String?
    let passAccuracy: String?
}

struct StageColor {
    static func color(for slug: String) -> (r: Double, g: Double, b: Double) {
        switch slug {
        case "group": return (0.043, 0.431, 0.310)
        case "r32": return (0.145, 0.388, 0.922)
        case "r16": return (0.031, 0.569, 0.698)
        case "qf": return (0.486, 0.227, 0.929)
        case "sf": return (0.918, 0.345, 0.047)
        case "third": return (0.392, 0.455, 0.545)
        case "final": return (0.831, 0.627, 0.090)
        default: return (0.043, 0.431, 0.310)
        }
    }
}

extension Date {
    func smartTime() -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = cal.component(.minute, from: self) == 0 ? "h a" : "h:mm a"
        return f.string(from: self)
    }

    func smartDateTime() -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMdjmm")
        return f.string(from: self)
    }
}
