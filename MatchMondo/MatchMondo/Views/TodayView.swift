import SwiftUI

struct TodayView: View {
    @EnvironmentObject var data: DataService
    @EnvironmentObject var scoreVisibility: ScoreVisibility
    @State private var expandedSections: Set<String> = ["Yesterday", "Today", "Tomorrow"]

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)
    private let greenDark = Color(red: 0.027, green: 0.322, blue: 0.231)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerBanner
                        .padding(.bottom, 8)

                    if data.isLoading {
                        ProgressView("Loading matches...")
                            .padding(.top, 60)
                    } else {
                        let yesterday = data.yesterdayMatches()
                        let today = data.todayMatches()
                        let tomorrow = data.tomorrowMatches()

                        if yesterday.isEmpty && today.isEmpty && tomorrow.isEmpty {
                            noMatchesView
                        } else {
                            VStack(spacing: 12) {
                                if !yesterday.isEmpty {
                                    daySection(title: "Yesterday", matches: yesterday)
                                }
                                if !today.isEmpty {
                                    daySection(title: "Today", matches: today)
                                }
                                if !tomorrow.isEmpty {
                                    daySection(title: "Tomorrow", matches: tomorrow)
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        statsBar
                            .padding(.top, 20)
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Color(red: 0.91, green: 0.94, blue: 0.91))
            .refreshable {
                await data.refresh()
            }
            .navigationTitle("MatchMondo")
            .navigationDestination(for: Match.self) { match in
                MatchDetailView(match: match)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if scoreVisibility.mode == .hideAll {
                            scoreVisibility.setMode(.all)
                        } else {
                            scoreVisibility.hide()
                        }
                    } label: {
                        Text(scoreVisibility.mode != .hideAll ? "Hide scores" : "Show scores")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .tint(green)
                }
            }
        }
    }

    private var headerBanner: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("World Cup 2026")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                if hasLiveMatches {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
            Text("June 11 \u{2013} July 19 \u{00b7} USA, Canada & Mexico")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [greenDark, green], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var hasLiveMatches: Bool {
        data.anyLive
    }

    private func daySection(title: String, matches: [Match]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if expandedSections.contains(title) {
                        expandedSections.remove(title)
                    } else {
                        expandedSections.insert(title)
                    }
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("\u{2014} \(formattedDate(matches.first!.kickoff))")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(matches.count) match\(matches.count == 1 ? "" : "es")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expandedSections.contains(title) ? 90 : 0))
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            .buttonStyle(.plain)

            if expandedSections.contains(title) {
                VStack(spacing: 8) {
                    ForEach(matches) { match in
                        NavigationLink(value: match) {
                            MatchCardView(match: match, showScore: scoreVisibility.shouldShowScore(for: match))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var noMatchesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sportscourt")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No matches in the next 3 days")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            let next = data.matches.first { $0.kickoff > Date() && !$0.hasScore }
            if let next {
                VStack(spacing: 4) {
                    Text("Next match")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(next.home) vs \(next.away)")
                        .font(.system(size: 15, weight: .bold))
                    Text(nextMatchDate(next.kickoff))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 60)
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            Label("\(data.playedCount) of \(data.totalCount) played", systemImage: "sportscourt.fill")
            if let updated = data.lastUpdated {
                Label("Updated \(updated, style: .relative) ago", systemImage: "arrow.clockwise")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    private func nextMatchDate(_ date: Date) -> String {
        date.smartDateTime()
    }
}
