import SwiftUI

struct MatchDetailView: View {
    let match: Match
    @EnvironmentObject var data: DataService
    private let green = Color(red: 0.043, green: 0.431, blue: 0.310)

    private var highlight: Highlight? {
        data.highlight(for: match.n)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                scoreHeader
                matchInfo
                highlightsSection
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color(red: 0.91, green: 0.94, blue: 0.91))
        .navigationTitle("Match \(match.n)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scoreHeader: some View {
        VStack(spacing: 12) {
            Text(match.stageLabel)
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    FlagView(team: match.home, size: 44)
                    Text(match.home)
                        .font(.system(size: 15, weight: .bold))
                    RankBadge(team: match.home)
                }
                .frame(maxWidth: .infinity)

                if match.hasScore {
                    let isLive = match.isLive
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Text("\(match.scoreH!)")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                            Text("–")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("\(match.scoreA!)")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(isLive ? green : .primary)

                        if isLive, let detail = match.liveDetail {
                            LiveBadge(detail: detail)
                        } else if match.hasScore {
                            Text("Full Time")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(spacing: 4) {
                        Text("vs")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(kickoffString)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 6) {
                    FlagView(team: match.away, size: 44)
                    Text(match.away)
                        .font(.system(size: 15, weight: .bold))
                    RankBadge(team: match.away)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var matchInfo: some View {
        VStack(spacing: 10) {
            infoRow(icon: "mappin.circle.fill", label: match.venue)
            infoRow(icon: "building.2.fill", label: match.city)
            infoRow(icon: "clock.fill", label: kickoffDateString)
            if let tv = match.tv {
                infoRow(icon: "tv.fill", label: tv)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    @ViewBuilder
    private var highlightsSection: some View {
        if let hl = highlight, (hl.short != nil || hl.extended != nil) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Highlights")
                    .font(.system(size: 18, weight: .bold))
                    .padding(.leading, 4)

                if let videoId = hl.short {
                    highlightCard(
                        videoId: videoId,
                        label: "Highlights",
                        icon: "play.rectangle.fill"
                    )
                }

                if let videoId = hl.extended {
                    highlightCard(
                        videoId: videoId,
                        label: "Extended Highlights",
                        icon: "film.fill"
                    )
                }
            }
        } else if match.hasScore && !match.isLive {
            VStack(spacing: 8) {
                Image(systemName: "film.stack")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Highlights coming soon")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }

    private func highlightCard(videoId: String, label: String, icon: String) -> some View {
        Button {
            if let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") {
                UIApplication.shared.open(url)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.15))
                            .aspectRatio(16/9, contentMode: .fill)
                            .overlay(
                                ProgressView()
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                    Text(label)
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(12)

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    private func infoRow(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(green)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private var kickoffString: String {
        match.kickoff.smartTime()
    }

    private var kickoffDateString: String {
        match.kickoff.smartDateTime()
    }
}
