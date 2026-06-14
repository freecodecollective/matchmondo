import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var data: DataService
    @EnvironmentObject var scoreVisibility: ScoreVisibility
    @State private var stageFilter = "All stages"
    @State private var searchText = ""

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)

    private var stages: [String] {
        var seen = Set<String>()
        var result = ["All stages"]
        for m in data.matches {
            if seen.insert(m.stage).inserted {
                result.append(m.stage)
            }
        }
        return result
    }

    private var filteredDays: [(date: Date, dayString: String, matches: [Match])] {
        data.matchesByDay().compactMap { day in
            let filtered = day.matches.filter { m in
                let stageOk = stageFilter == "All stages" || m.stage == stageFilter
                let searchOk = searchText.isEmpty ||
                    m.home.localizedCaseInsensitiveContains(searchText) ||
                    m.away.localizedCaseInsensitiveContains(searchText) ||
                    m.venue.localizedCaseInsensitiveContains(searchText) ||
                    m.city.localizedCaseInsensitiveContains(searchText)
                return stageOk && searchOk
            }
            return filtered.isEmpty ? nil : (day.date, day.dayString, filtered)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ScoreFilterBar()

                        ForEach(filteredDays, id: \.dayString) { day in
                            Section {
                                ForEach(day.matches) { match in
                                    NavigationLink(value: match) {
                                        MatchCardView(match: match, showScore: scoreVisibility.shouldShowScore(for: match))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                }
                            } header: {
                                HStack(spacing: 8) {
                                    Text(day.dayString)
                                        .font(.system(size: 14, weight: .bold))
                                    if Calendar.current.isDateInToday(day.date) {
                                        Text("Today")
                                            .font(.system(size: 10, weight: .bold))
                                            .textCase(.uppercase)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(green)
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                                .id(day.dayString)
                            }
                        }
                    }
                }
                .navigationDestination(for: Match.self) { match in
                    MatchDetailView(match: match)
                }
                .navigationDestination(for: String.self) { team in
                    TeamDetailView(team: team)
                }
                .background(Color(red: 0.91, green: 0.94, blue: 0.91))
                .onAppear {
                    scrollToToday(proxy: proxy)
                }
            }
            .navigationTitle("Schedule")
            .searchable(text: $searchText, prompt: "Search teams, venues...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(stages, id: \.self) { stage in
                            Button {
                                stageFilter = stage
                            } label: {
                                HStack {
                                    Text(stage)
                                    if stage == stageFilter {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable {
                await data.refresh()
            }
        }
    }

    private func scrollToToday(proxy: ScrollViewProxy) {
        let cal = Calendar.current
        if let todayDay = filteredDays.first(where: { cal.isDateInToday($0.date) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    proxy.scrollTo(todayDay.dayString, anchor: .top)
                }
            }
        }
    }
}
