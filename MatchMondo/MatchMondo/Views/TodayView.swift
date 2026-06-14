import SwiftUI

struct TodayView: View {
    @EnvironmentObject var data: DataService
    @State private var showScores = true

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
                        let today = data.todayMatches()
                        let tomorrow = data.tomorrowMatches()

                        if today.isEmpty && tomorrow.isEmpty {
                            noMatchesView
                        } else {
                            VStack(spacing: 16) {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $showScores) {
                        Image(systemName: showScores ? "eye.fill" : "eye.slash")
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                Text("\u{2014} \(formattedDate(matches.first!.kickoff))")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(matches.count) match\(matches.count == 1 ? "" : "es")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(matches) { match in
                MatchCardView(match: match, showScores: showScores)
            }
        }
    }

    private var noMatchesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sportscourt")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No matches today or tomorrow")
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
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        return f.string(from: date)
    }
}
