import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    settingToggle(
                        isOn: $appSettings.showFIFARankings,
                        title: "Show FIFA Rankings",
                        subtitle: "Display ranking badges next to team names"
                    )

                    Divider()

                    settingToggle(
                        isOn: $appSettings.showMatchLocations,
                        title: "Show Match Locations",
                        subtitle: "Display venue and city on match cards"
                    )

                    Divider()

                    settingToggle(
                        isOn: $appSettings.showCountryFlags,
                        title: "Show Country Flags",
                        subtitle: "Display flag icons next to team names"
                    )

                    Divider()

                    settingToggle(
                        isOn: $appSettings.showGameTimes,
                        title: "Show Game Times",
                        subtitle: "Display kickoff times on match cards"
                    )
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
        }
        .background(Color(red: 0.91, green: 0.94, blue: 0.91))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingToggle(isOn: Binding<Bool>, title: String, subtitle: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .tint(green)
    }
}
