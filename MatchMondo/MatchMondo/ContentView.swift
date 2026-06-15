import SwiftUI

struct ContentView: View {
    @EnvironmentObject var data: DataService

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("3-Day", systemImage: "clock.fill")
                }

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }

            StandingsView()
                .tabItem {
                    Label("Standings", systemImage: "chart.bar.fill")
                }

            TeamsView()
                .tabItem {
                    Label("Teams", systemImage: "flag.fill")
                }

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
        }
        .tint(Color(red: 0.043, green: 0.431, blue: 0.310))
        .preferredColorScheme(.light)
    }
}
