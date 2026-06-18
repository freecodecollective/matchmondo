import SwiftUI

struct MatchCardView: View {
    let match: Match
    var showScore: Bool = true
    var compact: Bool = false
    @EnvironmentObject var appSettings: AppSettings

    private var stageColor: Color {
        let c = StageColor.color(for: match.stageSlug)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    private var homeWin: Bool {
        showScore && match.hasScore && match.scoreH! > match.scoreA!
    }

    private var awayWin: Bool {
        showScore && match.hasScore && match.scoreA! > match.scoreH!
    }

    private var timeString: String {
        match.kickoff.smartTime()
    }

    private var isCompleted: Bool {
        showScore && match.hasScore && !match.isLive
    }

    private var cardBackground: Color {
        if isCompleted {
            return Color(red: 0.949, green: 0.953, blue: 0.949)
        }
        return Color(.systemBackground)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if match.isLive {
                    LiveBadge(detail: match.liveDetail)
                } else if appSettings.showGameTimes {
                    Text(timeString)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Match \(match.n) · \(match.stage == "Final" ? "🏆 " : "")\(match.stageLabel)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(match.stageSlug == "group" ? .secondary : stageColor)
                    .textCase(.uppercase)
            }
            .padding(.bottom, 8)

            HStack(spacing: 0) {
                TeamNameView(team: match.home, isWinner: homeWin)

                Spacer()

                if showScore && match.hasScore {
                    let h = match.scoreH!
                    let a = match.scoreA!
                    HStack(spacing: 6) {
                        Text("\(h)")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("–")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("\(a)")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text("vs")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }

                Spacer()

                TeamNameView(team: match.away, isWinner: awayWin)
            }

            if !compact && appSettings.showMatchLocations {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 11))
                    Text("\(match.venue)")
                        .font(.system(size: 12, weight: .semibold))
                    Text("· \(match.city)")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            HStack(spacing: 0) {
                stageColor
                    .frame(width: 4)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12))
                Spacer()
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(match.isLive ? Color(red: 0.043, green: 0.431, blue: 0.310) : Color(.separator).opacity(0.3),
                        lineWidth: match.isLive ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

struct LiveBadge: View {
    let detail: String?

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
                .opacity(pulse ? 0.4 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            Text(detail ?? "LIVE")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
        }
    }
}
