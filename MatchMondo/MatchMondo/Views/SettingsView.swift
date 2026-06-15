import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @State private var showRestartAlert = false

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)

    private let supportedLanguages: [(code: String, name: String)] = [
        ("system", "System Default"),
        ("en", "English"),
        ("ja", "日本語"),
    ]

    private var selectedLanguage: String {
        if let override = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
           let first = override.first,
           supportedLanguages.contains(where: { $0.code == first }) {
            return first
        }
        return "system"
    }

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

                    Divider()

                    languagePicker
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
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Close App") {
                exit(0)
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Please close and reopen MatchMondo to apply the language change.")
        }
    }

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Language")
                .font(.system(size: 15, weight: .medium))
            Text("Override your device language for this app")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Picker("Language", selection: Binding(
                get: { selectedLanguage },
                set: { newValue in
                    if newValue == "system" {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                    }
                    showRestartAlert = true
                }
            )) {
                ForEach(supportedLanguages, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)
        }
    }

    private func settingToggle(isOn: Binding<Bool>, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
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
