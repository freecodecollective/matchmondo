import SwiftUI

struct MatchDetailView: View {
    let match: Match
    @EnvironmentObject var data: DataService
    @EnvironmentObject var scoreVisibility: ScoreVisibility
    @State private var scoreRevealed = false
    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)
    private let gold = Color(red: 0.91, green: 0.725, blue: 0.137)

    private var shouldHideScore: Bool {
        guard match.hasScore, !scoreRevealed else { return false }
        if scoreVisibility.shouldShowScore(for: match) { return false }
        let cal = Calendar.current
        return cal.isDateInToday(match.kickoff) || cal.isDateInYesterday(match.kickoff)
    }

    private var highlight: Highlight? {
        data.highlight(for: match.n)
    }

    private var detail: MatchDetail? {
        data.matchDetails[match.n]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                scoreHeader
                if !shouldHideScore, let detail, !detail.events.isEmpty {
                    goalsSummary(detail.events)
                }
                highlightsSection
                if let detail, detail.homeStats != nil, detail.awayStats != nil {
                    statsSection(detail)
                }
                if let detail, !detail.events.isEmpty {
                    cardsSection(detail.events)
                }
                if let detail, !detail.events.isEmpty {
                    substitutions(detail.events)
                }
                matchInfo
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Color(red: 0.91, green: 0.94, blue: 0.91))
        .navigationTitle("Match \(match.n)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { team in
            TeamDetailView(team: team)
        }
        .task {
            await data.fetchMatchDetail(for: match)
        }
    }

    // MARK: - Score Header

    private var scoreHeader: some View {
        VStack(spacing: 12) {
            Text(match.stageLabel)
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                NavigationLink(value: match.home) {
                    VStack(spacing: 6) {
                        FlagView(team: match.home, size: 44)
                        Text(match.home)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                        RankBadge(team: match.home)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                if match.hasScore && shouldHideScore {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text("?")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("–")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("?")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundStyle(.secondary.opacity(0.4))
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scoreRevealed = true
                            }
                        } label: {
                            Label("Show Score", systemImage: "eye")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(green)
                                .clipShape(Capsule())
                        }
                    }
                } else if match.hasScore {
                    let isLive = match.isLive
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Text("\(match.scoreH!)")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                            Text("–")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("\(match.scoreA!)")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(isLive ? green : .primary)

                        if isLive, let detail = match.liveDetail {
                            LiveBadge(detail: detail)
                        } else if match.hasScore {
                            Text("Full Time")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(spacing: 4) {
                        Text("vs")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(kickoffString)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink(value: match.away) {
                    VStack(spacing: 6) {
                        FlagView(team: match.away, size: 44)
                        Text(match.away)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                        RankBadge(team: match.away)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Events Timeline

    @ViewBuilder
    private func goalsSummary(_ events: [MatchEvent]) -> some View {
        let goals = events.filter { [.goal, .penaltyGoal, .ownGoal].contains($0.type) }
        if !goals.isEmpty {
            eventGroup(title: "Goals", icon: "sportscourt.fill", events: goals)
        }
    }

    @ViewBuilder
    private func cardsSection(_ events: [MatchEvent]) -> some View {
        let cards = events.filter { [.yellowCard, .redCard, .secondYellow].contains($0.type) }
        if !cards.isEmpty {
            eventGroup(title: "Cards", icon: "rectangle.portrait.fill", events: cards)
        }
    }

    @ViewBuilder
    private func substitutions(_ events: [MatchEvent]) -> some View {
        let subs = events.filter { $0.type == .substitution }
        if !subs.isEmpty {
            eventGroup(title: "Substitutions", icon: "arrow.left.arrow.right", events: subs)
        }
    }

    private func eventGroup(title: String, icon: String, events: [MatchEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(green)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                eventRow(event)
                if index < events.count - 1 {
                    Divider().padding(.leading, 48)
                }
            }
        }
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func eventRow(_ event: MatchEvent) -> some View {
        let isHome = event.teamName == espnName(for: match.home)

        return HStack(spacing: 10) {
            Text(event.minute)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)

            eventIcon(event.type)

            VStack(alignment: .leading, spacing: 2) {
                switch event.type {
                case .goal, .penaltyGoal, .ownGoal:
                    HStack(spacing: 4) {
                        Text(event.playerName)
                            .font(.system(size: 14, weight: .bold))
                        if event.type == .penaltyGoal {
                            Text("(penalty)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else if event.type == .ownGoal {
                            Text("(own goal)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    if let assist = event.assistName {
                        Text("Assist: \(assist)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                case .yellowCard, .redCard, .secondYellow:
                    Text(event.playerName)
                        .font(.system(size: 14, weight: .semibold))

                case .substitution:
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                        Text(event.playerName)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    if let playerOut = event.playerOut {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.red)
                            Text(playerOut)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            FlagView(team: isHome ? match.home : match.away, size: 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func eventIcon(_ type: MatchEventType) -> some View {
        Group {
            switch type {
            case .goal, .penaltyGoal:
                Image(systemName: "soccerball")
                    .font(.system(size: 14))
                    .foregroundStyle(green)
            case .ownGoal:
                Image(systemName: "soccerball")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
            case .yellowCard:
                RoundedRectangle(cornerRadius: 1)
                    .fill(.yellow)
                    .frame(width: 10, height: 14)
            case .redCard:
                RoundedRectangle(cornerRadius: 1)
                    .fill(.red)
                    .frame(width: 10, height: 14)
            case .secondYellow:
                ZStack {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.yellow)
                        .frame(width: 10, height: 14)
                        .offset(x: -2)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.red)
                        .frame(width: 10, height: 14)
                        .offset(x: 2)
                }
            case .substitution:
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 20)
    }

    // MARK: - Stats

    private func statsSection(_ detail: MatchDetail) -> some View {
        guard let home = detail.homeStats, let away = detail.awayStats else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(green)
                    Text("Match Stats")
                        .font(.system(size: 15, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

                VStack(spacing: 8) {
                    if let hp = home.possession, let ap = away.possession {
                        statBar(label: "Possession", homeVal: "\(hp)%", awayVal: "\(ap)%",
                                homePct: Double(hp) ?? 50, awayPct: Double(ap) ?? 50)
                    }
                    if let hs = home.shots, let as_ = away.shots {
                        statBar(label: "Shots", homeVal: hs, awayVal: as_,
                                homePct: Double(hs) ?? 0, awayPct: Double(as_) ?? 0)
                    }
                    if let hs = home.shotsOnGoal, let as_ = away.shotsOnGoal {
                        statBar(label: "Shots on Target", homeVal: hs, awayVal: as_,
                                homePct: Double(hs) ?? 0, awayPct: Double(as_) ?? 0)
                    }
                    if let hc = home.corners, let ac = away.corners {
                        statBar(label: "Corners", homeVal: hc, awayVal: ac,
                                homePct: Double(hc) ?? 0, awayPct: Double(ac) ?? 0)
                    }
                    if let hf = home.fouls, let af = away.fouls {
                        statBar(label: "Fouls", homeVal: hf, awayVal: af,
                                homePct: Double(hf) ?? 0, awayPct: Double(af) ?? 0)
                    }
                    if let ho = home.offsides, let ao = away.offsides {
                        statBar(label: "Offsides", homeVal: ho, awayVal: ao,
                                homePct: Double(ho) ?? 0, awayPct: Double(ao) ?? 0)
                    }
                    if let hs = home.saves, let as_ = away.saves {
                        statBar(label: "Saves", homeVal: hs, awayVal: as_,
                                homePct: Double(hs) ?? 0, awayPct: Double(as_) ?? 0)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
    }

    private func statBar(label: String, homeVal: String, awayVal: String, homePct: Double, awayPct: Double) -> some View {
        let total = max(homePct + awayPct, 1)
        let homeRatio = homePct / total
        let awayRatio = awayPct / total

        return VStack(spacing: 3) {
            HStack {
                Text(homeVal)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(width: 40, alignment: .leading)
                Spacer()
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(awayVal)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(width: 40, alignment: .trailing)
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(green)
                        .frame(width: max(geo.size.width * homeRatio - 1, 4))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(green.opacity(0.3))
                        .frame(width: max(geo.size.width * awayRatio - 1, 4))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Match Info

    private var matchInfo: some View {
        VStack(spacing: 10) {
            infoRow(icon: "mappin.circle.fill", label: match.venue)
            infoRow(icon: "building.2.fill", label: match.city)
            infoRow(icon: "clock.fill", label: kickoffDateString)
            if let tv = match.tv {
                infoRow(icon: "tv.fill", label: tv)
            }
            if let detail {
                if let ref = detail.referee {
                    infoRow(icon: "person.badge.shield.checkmark", label: ref)
                }
                if let att = detail.attendance {
                    infoRow(icon: "person.3.fill", label: "\(formatNumber(att)) attendance")
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Highlights

    @ViewBuilder
    private var highlightsSection: some View {
        if let hl = highlight, (hl.short != nil || hl.extended != nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(green)
                    Text("Highlights")
                        .font(.system(size: 15, weight: .bold))
                }
                .padding(.leading, 4)

                if hl.short != nil && hl.extended != nil {
                    HStack(spacing: 10) {
                        highlightCard(
                            videoId: hl.short!,
                            label: "Highlights",
                            icon: "play.rectangle.fill",
                            duration: hl.shortDuration
                        )
                        highlightCard(
                            videoId: hl.extended!,
                            label: "Extended",
                            icon: "film.fill",
                            duration: hl.extendedDuration
                        )
                    }
                } else if let videoId = hl.short {
                    highlightCard(
                        videoId: videoId,
                        label: "Highlights",
                        icon: "play.rectangle.fill",
                        duration: hl.shortDuration
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxWidth: 240)
                } else if let videoId = hl.extended {
                    highlightCard(
                        videoId: videoId,
                        label: "Extended",
                        icon: "film.fill",
                        duration: hl.extendedDuration
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxWidth: 240)
                }
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        } else if match.hasScore && !match.isLive {
            VStack(spacing: 8) {
                Image(systemName: "film.stack")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Highlights coming soon")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    private func highlightCard(videoId: String, label: String, icon: String, duration: String? = nil) -> some View {
        Button {
            if let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") {
                UIApplication.shared.open(url)
            }
        } label: {
            ZStack {
                AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.15))
                            .aspectRatio(16/9, contentMode: .fill)
                            .overlay(ProgressView())
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))

                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))

                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(label)
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)

                        Spacer()

                        if let duration {
                            Text(duration)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func goalScorers(for team: String) -> some View {
        if let detail {
            let goals = detail.events.filter {
                [.goal, .penaltyGoal, .ownGoal].contains($0.type) && $0.teamName == team
            }
            if !goals.isEmpty {
                VStack(spacing: 2) {
                    ForEach(goals) { goal in
                        let suffix = goal.type == .penaltyGoal ? " (P)" : goal.type == .ownGoal ? " (OG)" : ""
                        Text("\(goal.playerName) \(goal.minute)'\(suffix)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func infoRow(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(green)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func espnName(for team: String) -> String {
        let reverseMap: [String: String] = [
            "Korea Republic": "South Korea", "USA": "United States",
            "Bosnia and Herzegovina": "Bosnia-Herzegovina", "Cabo Verde": "Cape Verde",
            "Côte d'Ivoire": "Ivory Coast", "IR Iran": "Iran",
        ]
        return reverseMap[team] ?? team
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private var kickoffString: String {
        match.kickoff.smartTime()
    }

    private var kickoffDateString: String {
        match.kickoff.smartDateTime()
    }
}
