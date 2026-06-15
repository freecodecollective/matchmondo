import SwiftUI

struct MoreView: View {
    @EnvironmentObject var appSettings: AppSettings

    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)
    private let greenDark = Color(red: 0.027, green: 0.322, blue: 0.231)

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                    .id("moreTop")
                }
                .onAppear {
                    proxy.scrollTo("moreTop", anchor: .top)
                }
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
        NavigationLink {
            SettingsView()
        } label: {
            HStack {
                Label("Settings", systemImage: "gearshape.fill")
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
            Label("Support Genesis Oakland", systemImage: "heart.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(green)

            Text("MatchMondo is free and always will be — no ads, no subscriptions. If you'd like to give back, consider donating to Genesis Oakland — a youth soccer club building community and creating opportunity for kids in Oakland through the beautiful game.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Link(destination: URL(string: "https://secure.givelively.org/donate/oakland-genesis-soccer-club-corporation/sobrante-field-a-soccer-sanctuary")!) {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("Donate to Genesis Oakland")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(green)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text("Or we can donate for you — just Venmo @busselle and we'll pass along the donation to Genesis Oakland.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            Link(destination: URL(string: "venmo://paycharge?txn=pay&recipients=busselle&note=MatchMondo%20donation%20for%20Genesis%20Oakland")!) {
                HStack {
                    Image(systemName: "dollarsign.circle")
                    Text("Donate via Venmo (@busselle, 2515)")
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
