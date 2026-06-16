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
    let why_es: String?
    let why_fr: String?
    let why_pt_BR: String?
    let why_de: String?
    let why_it: String?
    let why_ja: String?
    let why_ko: String?
    let why_zh_Hans: String?
    let why_ar: String?
    let why_es_ES: String?

    var localizedWhy: String {
        let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] ?? []
        let lang = langs.first ?? ""
        if lang.hasPrefix("es-ES") { return why_es_ES ?? why }
        if lang.hasPrefix("es") { return why_es ?? why }
        if lang.hasPrefix("fr") { return why_fr ?? why }
        if lang.hasPrefix("pt") { return why_pt_BR ?? why }
        if lang.hasPrefix("de") { return why_de ?? why }
        if lang.hasPrefix("it") { return why_it ?? why }
        if lang.hasPrefix("ja") { return why_ja ?? why }
        if lang.hasPrefix("ko") { return why_ko ?? why }
        if lang.hasPrefix("zh") { return why_zh_Hans ?? why }
        if lang.hasPrefix("ar") { return why_ar ?? why }
        return why
    }
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

enum TeamNames {
    private static let translations: [String: [String: String]] = [
        "Algeria": ["es": "Argelia", "fr": "Algérie", "pt": "Argélia", "de": "Algerien", "it": "Algeria", "ja": "アルジェリア", "ko": "알제리", "zh": "阿尔及利亚", "ar": "الجزائر"],
        "Argentina": ["es": "Argentina", "fr": "Argentine", "pt": "Argentina", "de": "Argentinien", "it": "Argentina", "ja": "アルゼンチン", "ko": "아르헨티나", "zh": "阿根廷", "ar": "الأرجنتين"],
        "Australia": ["es": "Australia", "fr": "Australie", "pt": "Austrália", "de": "Australien", "it": "Australia", "ja": "オーストラリア", "ko": "호주", "zh": "澳大利亚", "ar": "أستراليا"],
        "Austria": ["es": "Austria", "fr": "Autriche", "pt": "Áustria", "de": "Österreich", "it": "Austria", "ja": "オーストリア", "ko": "오스트리아", "zh": "奥地利", "ar": "النمسا"],
        "Belgium": ["es": "Bélgica", "fr": "Belgique", "pt": "Bélgica", "de": "Belgien", "it": "Belgio", "ja": "ベルギー", "ko": "벨기에", "zh": "比利时", "ar": "بلجيكا"],
        "Bosnia and Herzegovina": ["es": "Bosnia y Herzegovina", "fr": "Bosnie-Herzégovine", "pt": "Bósnia e Herzegovina", "de": "Bosnien und Herzegowina", "it": "Bosnia ed Erzegovina", "ja": "ボスニア・ヘルツェゴビナ", "ko": "보스니아 헤르체고비나", "zh": "波黑", "ar": "البوسنة والهرسك"],
        "Brazil": ["es": "Brasil", "fr": "Brésil", "pt": "Brasil", "de": "Brasilien", "it": "Brasile", "ja": "ブラジル", "ko": "브라질", "zh": "巴西", "ar": "البرازيل"],
        "Cabo Verde": ["es": "Cabo Verde", "fr": "Cap-Vert", "pt": "Cabo Verde", "de": "Kap Verde", "it": "Capo Verde", "ja": "カーボベルデ", "ko": "카보베르데", "zh": "佛得角", "ar": "الرأس الأخضر"],
        "Canada": ["es": "Canadá", "fr": "Canada", "pt": "Canadá", "de": "Kanada", "it": "Canada", "ja": "カナダ", "ko": "캐나다", "zh": "加拿大", "ar": "كندا"],
        "Colombia": ["es": "Colombia", "fr": "Colombie", "pt": "Colômbia", "de": "Kolumbien", "it": "Colombia", "ja": "コロンビア", "ko": "콜롬비아", "zh": "哥伦比亚", "ar": "كولومبيا"],
        "Congo DR": ["es": "RD del Congo", "fr": "RD Congo", "pt": "RD Congo", "de": "DR Kongo", "it": "RD Congo", "ja": "コンゴ民主共和国", "ko": "콩고민주공화국", "zh": "刚果民主共和国", "ar": "الكونغو الديمقراطية"],
        "Croatia": ["es": "Croacia", "fr": "Croatie", "pt": "Croácia", "de": "Kroatien", "it": "Croazia", "ja": "クロアチア", "ko": "크로아티아", "zh": "克罗地亚", "ar": "كرواتيا"],
        "Curaçao": ["es": "Curazao", "fr": "Curaçao", "pt": "Curaçao", "de": "Curaçao", "it": "Curaçao", "ja": "キュラソー", "ko": "퀴라소", "zh": "库拉索", "ar": "كوراساو"],
        "Czechia": ["es": "Chequia", "fr": "Tchéquie", "pt": "Tchéquia", "de": "Tschechien", "it": "Cechia", "ja": "チェコ", "ko": "체코", "zh": "捷克", "ar": "التشيك"],
        "Côte d'Ivoire": ["es": "Costa de Marfil", "fr": "Côte d'Ivoire", "pt": "Costa do Marfim", "de": "Elfenbeinküste", "it": "Costa d'Avorio", "ja": "コートジボワール", "ko": "코트디부아르", "zh": "科特迪瓦", "ar": "ساحل العاج"],
        "Ecuador": ["es": "Ecuador", "fr": "Équateur", "pt": "Equador", "de": "Ecuador", "it": "Ecuador", "ja": "エクアドル", "ko": "에콰도르", "zh": "厄瓜多尔", "ar": "الإكوادور"],
        "Egypt": ["es": "Egipto", "fr": "Égypte", "pt": "Egito", "de": "Ägypten", "it": "Egitto", "ja": "エジプト", "ko": "이집트", "zh": "埃及", "ar": "مصر"],
        "England": ["es": "Inglaterra", "fr": "Angleterre", "pt": "Inglaterra", "de": "England", "it": "Inghilterra", "ja": "イングランド", "ko": "잉글랜드", "zh": "英格兰", "ar": "إنجلترا"],
        "France": ["es": "Francia", "fr": "France", "pt": "França", "de": "Frankreich", "it": "Francia", "ja": "フランス", "ko": "프랑스", "zh": "法国", "ar": "فرنسا"],
        "Germany": ["es": "Alemania", "fr": "Allemagne", "pt": "Alemanha", "de": "Deutschland", "it": "Germania", "ja": "ドイツ", "ko": "독일", "zh": "德国", "ar": "ألمانيا"],
        "Ghana": ["es": "Ghana", "fr": "Ghana", "pt": "Gana", "de": "Ghana", "it": "Ghana", "ja": "ガーナ", "ko": "가나", "zh": "加纳", "ar": "غانا"],
        "Haiti": ["es": "Haití", "fr": "Haïti", "pt": "Haiti", "de": "Haiti", "it": "Haiti", "ja": "ハイチ", "ko": "아이티", "zh": "海地", "ar": "هايتي"],
        "IR Iran": ["es": "Irán", "fr": "Iran", "pt": "Irã", "de": "Iran", "it": "Iran", "ja": "イラン", "ko": "이란", "zh": "伊朗", "ar": "إيران"],
        "Iraq": ["es": "Irak", "fr": "Irak", "pt": "Iraque", "de": "Irak", "it": "Iraq", "ja": "イラク", "ko": "이라크", "zh": "伊拉克", "ar": "العراق"],
        "Japan": ["es": "Japón", "fr": "Japon", "pt": "Japão", "de": "Japan", "it": "Giappone", "ja": "日本", "ko": "일본", "zh": "日本", "ar": "اليابان"],
        "Jordan": ["es": "Jordania", "fr": "Jordanie", "pt": "Jordânia", "de": "Jordanien", "it": "Giordania", "ja": "ヨルダン", "ko": "요르단", "zh": "约旦", "ar": "الأردن"],
        "Korea Republic": ["es": "Corea del Sur", "fr": "Corée du Sud", "pt": "Coreia do Sul", "de": "Südkorea", "it": "Corea del Sud", "ja": "韓国", "ko": "대한민국", "zh": "韩国", "ar": "كوريا الجنوبية"],
        "Mexico": ["es": "México", "fr": "Mexique", "pt": "México", "de": "Mexiko", "it": "Messico", "ja": "メキシコ", "ko": "멕시코", "zh": "墨西哥", "ar": "المكسيك"],
        "Morocco": ["es": "Marruecos", "fr": "Maroc", "pt": "Marrocos", "de": "Marokko", "it": "Marocco", "ja": "モロッコ", "ko": "모로코", "zh": "摩洛哥", "ar": "المغرب"],
        "Netherlands": ["es": "Países Bajos", "fr": "Pays-Bas", "pt": "Países Baixos", "de": "Niederlande", "it": "Paesi Bassi", "ja": "オランダ", "ko": "네덜란드", "zh": "荷兰", "ar": "هولندا"],
        "New Zealand": ["es": "Nueva Zelanda", "fr": "Nouvelle-Zélande", "pt": "Nova Zelândia", "de": "Neuseeland", "it": "Nuova Zelanda", "ja": "ニュージーランド", "ko": "뉴질랜드", "zh": "新西兰", "ar": "نيوزيلندا"],
        "Norway": ["es": "Noruega", "fr": "Norvège", "pt": "Noruega", "de": "Norwegen", "it": "Norvegia", "ja": "ノルウェー", "ko": "노르웨이", "zh": "挪威", "ar": "النرويج"],
        "Panama": ["es": "Panamá", "fr": "Panama", "pt": "Panamá", "de": "Panama", "it": "Panama", "ja": "パナマ", "ko": "파나마", "zh": "巴拿马", "ar": "بنما"],
        "Paraguay": ["es": "Paraguay", "fr": "Paraguay", "pt": "Paraguai", "de": "Paraguay", "it": "Paraguay", "ja": "パラグアイ", "ko": "파라과이", "zh": "巴拉圭", "ar": "باراغواي"],
        "Portugal": ["es": "Portugal", "fr": "Portugal", "pt": "Portugal", "de": "Portugal", "it": "Portogallo", "ja": "ポルトガル", "ko": "포르투갈", "zh": "葡萄牙", "ar": "البرتغال"],
        "Qatar": ["es": "Catar", "fr": "Qatar", "pt": "Catar", "de": "Katar", "it": "Qatar", "ja": "カタール", "ko": "카타르", "zh": "卡塔尔", "ar": "قطر"],
        "Saudi Arabia": ["es": "Arabia Saudita", "fr": "Arabie saoudite", "pt": "Arábia Saudita", "de": "Saudi-Arabien", "it": "Arabia Saudita", "ja": "サウジアラビア", "ko": "사우디아라비아", "zh": "沙特阿拉伯", "ar": "السعودية"],
        "Scotland": ["es": "Escocia", "fr": "Écosse", "pt": "Escócia", "de": "Schottland", "it": "Scozia", "ja": "スコットランド", "ko": "스코틀랜드", "zh": "苏格兰", "ar": "اسكتلندا"],
        "Senegal": ["es": "Senegal", "fr": "Sénégal", "pt": "Senegal", "de": "Senegal", "it": "Senegal", "ja": "セネガル", "ko": "세네갈", "zh": "塞内加尔", "ar": "السنغال"],
        "South Africa": ["es": "Sudáfrica", "fr": "Afrique du Sud", "pt": "África do Sul", "de": "Südafrika", "it": "Sudafrica", "ja": "南アフリカ", "ko": "남아공", "zh": "南非", "ar": "جنوب أفريقيا"],
        "Spain": ["es": "España", "fr": "Espagne", "pt": "Espanha", "de": "Spanien", "it": "Spagna", "ja": "スペイン", "ko": "스페인", "zh": "西班牙", "ar": "إسبانيا"],
        "Sweden": ["es": "Suecia", "fr": "Suède", "pt": "Suécia", "de": "Schweden", "it": "Svezia", "ja": "スウェーデン", "ko": "스웨덴", "zh": "瑞典", "ar": "السويد"],
        "Switzerland": ["es": "Suiza", "fr": "Suisse", "pt": "Suíça", "de": "Schweiz", "it": "Svizzera", "ja": "スイス", "ko": "스위스", "zh": "瑞士", "ar": "سويسرا"],
        "Tunisia": ["es": "Túnez", "fr": "Tunisie", "pt": "Tunísia", "de": "Tunesien", "it": "Tunisia", "ja": "チュニジア", "ko": "튀니지", "zh": "突尼斯", "ar": "تونس"],
        "Türkiye": ["es": "Turquía", "fr": "Türkiye", "pt": "Turquia", "de": "Türkei", "it": "Turchia", "ja": "トルコ", "ko": "튀르키예", "zh": "土耳其", "ar": "تركيا"],
        "USA": ["es": "EE. UU.", "fr": "États-Unis", "pt": "EUA", "de": "USA", "it": "USA", "ja": "アメリカ", "ko": "미국", "zh": "美国", "ar": "الولايات المتحدة"],
        "Uruguay": ["es": "Uruguay", "fr": "Uruguay", "pt": "Uruguai", "de": "Uruguay", "it": "Uruguay", "ja": "ウルグアイ", "ko": "우루과이", "zh": "乌拉圭", "ar": "أوروغواي"],
        "Uzbekistan": ["es": "Uzbekistán", "fr": "Ouzbékistan", "pt": "Uzbequistão", "de": "Usbekistan", "it": "Uzbekistan", "ja": "ウズベキスタン", "ko": "우즈베키스탄", "zh": "乌兹别克斯坦", "ar": "أوزبكستان"],
    ]

    static func localizedName(for team: String) -> String {
        let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] ?? []
        let lang = langs.first ?? ""
        guard let map = translations[team] else { return team }
        if lang.hasPrefix("es") { return map["es"] ?? team }
        if lang.hasPrefix("fr") { return map["fr"] ?? team }
        if lang.hasPrefix("pt") { return map["pt"] ?? team }
        if lang.hasPrefix("de") { return map["de"] ?? team }
        if lang.hasPrefix("it") { return map["it"] ?? team }
        if lang.hasPrefix("ja") { return map["ja"] ?? team }
        if lang.hasPrefix("ko") { return map["ko"] ?? team }
        if lang.hasPrefix("zh") { return map["zh"] ?? team }
        if lang.hasPrefix("ar") { return map["ar"] ?? team }
        return team
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
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.component(.minute, from: self) == 0 {
            f.setLocalizedDateFormatFromTemplate("j")
        } else {
            f.setLocalizedDateFormatFromTemplate("jmm")
        }
        return f.string(from: self)
    }

    func smartDateTime() -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMdjmm")
        return f.string(from: self)
    }
}
