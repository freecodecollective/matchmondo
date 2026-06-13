import SwiftUI

struct ContentView: View {
    @EnvironmentObject var data: DataService

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "clock.fill")
                }

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }

            StandingsView()
                .tabItem {
                    Label("Standings", systemImage: "chart.bar.fill")
                }

            PlayersView()
                .tabItem {
                    Label("Players", systemImage: "star.fill")
                }

            RulesView()
                .tabItem {
                    Label("Rules", systemImage: "list.clipboard.fill")
                }
        }
        .tint(Color(red: 0.043, green: 0.431, blue: 0.310))
    }
}
