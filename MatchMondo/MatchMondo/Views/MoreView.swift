import SwiftUI

struct MoreView: View {
    @EnvironmentObject var appSettings: AppSettings

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)
    private let greenDark = Color(red: 0.027, green: 0.322, blue: 0.231)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    aboutSection
                    supportSection
                    settingsSection
                    rulesLink
                    feedbackSection
                    appInfoSection
                }
                .padding(.vertical, 12)
            }
            .background(Color(red: 0.91, green: 0.94, blue: 0.91))
            .navigationTitle("More")
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("About MatchMondo", systemImage: "info.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(green)

            Text("Built by a group of passionate football fans in California who wanted a better way to follow the 2026 World Cup. We built this app for ourselves — and we're grateful anyone else has found it useful.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Settings", systemImage: "gearshape.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(green)

            Toggle(isOn: $appSettings.showFIFARankings) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show FIFA Rankings")
                        .font(.system(size: 15, weight: .medium))
                    Text("Display ranking badges next to team names")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var rulesLink: some View {
        NavigationLink {
            RulesView()
        } label: {
            HStack {
                Label("Tournament Rules", systemImage: "list.clipboard.fill")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Support Soccer without Borders", systemImage: "heart.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(green)

            Text("MatchMondo is free and always will be. If you'd like to give back, consider donating to Soccer without Borders — a nonprofit that uses soccer to help refugee and immigrant youth build community and opportunity.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Text("Suggested donation: $1–$5")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Link(destination: URL(string: "https://www.soccerwithoutborders.org/donate")!) {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("Donate to Soccer without Borders")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(green)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Feature Requests", systemImage: "envelope.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(green)

            Text("Have an idea to make MatchMondo better? We'd love to hear it.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Link(destination: URL(string: "mailto:chris@tidygolinks.com?subject=MatchMondo%20Feature%20Request")!) {
                HStack {
                    Image(systemName: "envelope")
                    Text("Email us a feature request")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(green)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var appInfoSection: some View {
        VStack(spacing: 4) {
            Text("MatchMondo v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text("Made with \u{2764}\u{fe0f} in California")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}
