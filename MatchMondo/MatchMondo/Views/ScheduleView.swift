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
                    TeamNames.localizedName(for: m.home).localizedCaseInsensitiveContains(searchText) ||
                    TeamNames.localizedName(for: m.away).localizedCaseInsensitiveContains(searchText) ||
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
                        ElectricHeaderBanner(style: .compact, title: "Schedule")

                        searchField

                        ScoreFilterBar()

                        stageFilterBar

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
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await data.refresh()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            TextField("Search teams, venues...", text: $searchText)
                .font(.system(size: 15))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var stageFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stages, id: \.self) { stage in
                    Button {
                        stageFilter = stage
                    } label: {
                        Text(LocalizedStringKey(stage))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(stage == stageFilter ? .white : .primary)
                            .background(stage == stageFilter ? green : Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
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
