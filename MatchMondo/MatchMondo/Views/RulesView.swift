import SwiftUI

struct RulesView: View {
    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("A fan's guide to the laws and tournament rules for Football 2026.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                ruleCard(
                    icon: "clock.fill",
                    title: "Match Format",
                    body: "Two 45-minute halves plus stoppage time. Group-stage matches can end in a draw. From the Round of 32 on, a tie after 90 minutes goes to two 15-minute periods of extra time, and if still level, a penalty shootout decides it."
                )

                ruleCard(
                    icon: "square.fill",
                    iconColor: .yellow,
                    title: "Yellow Card (Caution)",
                    body: "A warning for unsporting behavior, dissent, persistent fouling, time-wasting, not respecting required distance at free kicks/corners, or entering/leaving the field without permission."
                )

                ruleCard(
                    icon: "square.fill",
                    iconColor: .red,
                    title: "Red Card (Sending-off)",
                    body: "Shown for serious foul play, violent conduct, spitting, denying an obvious goal-scoring opportunity, offensive language, or two yellow cards in the same match. The player leaves and cannot be replaced — the team plays short."
                )

                ruleCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Suspensions & Amnesty",
                    body: "Two yellows in different matches = one-match suspension. Single yellows are wiped after the group stage, and wiped again after the quarter-finals, so a player can't miss the final from an early caution."
                )

                ruleCard(
                    icon: "chart.bar.fill",
                    title: "Group Tiebreakers",
                    body: "If teams are level on points: 1) Goal difference, 2) Goals scored, 3) Head-to-head points, 4) Head-to-head GD, 5) Head-to-head goals scored, 6) Fair-play score, 7) Drawing of lots."
                )

                ruleCard(
                    icon: "arrow.right.circle.fill",
                    title: "Who Advances",
                    body: "48 teams in 12 groups. The top two from each group (24 teams) advance, plus the 8 best third-placed teams — 32 teams into the Round of 32."
                )

                Text("Unofficial summary for fans. See the official tournament website for regulations.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        }
        .background(Color(red: 0.91, green: 0.94, blue: 0.91))
        .navigationTitle("Tournament Rules")
    }

    private func ruleCard(icon: String, iconColor: Color = Color(red: 0.043, green: 0.431, blue: 0.310), title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 16, weight: .bold))
            }

            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            HStack(spacing: 0) {
                green
                    .frame(width: 4)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12))
                Spacer()
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}
