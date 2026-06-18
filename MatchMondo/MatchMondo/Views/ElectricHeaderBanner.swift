import SwiftUI

struct ElectricHeaderBanner: View {
    enum Style { case full, compact }

    let style: Style
    let title: String
    @EnvironmentObject var data: DataService

    @State private var shimmerPhase: CGFloat = -1
    @State private var shimmerOpacity: Double = 1.0
    @State private var ballOffset: CGFloat = 0
    @State private var ballRotation: Double = 0
    @State private var ballOpacity: Double = 0.7
    @State private var glowOpacity: Double = 0.12

    static let bannerColor = Color(red: 0.043, green: 0.373, blue: 0.259)
    private let darkGreen = Color(red: 0.027, green: 0.322, blue: 0.231)
    private let lineColor = Color.white.opacity(0.18)
    private let pitchLineColor = Color(red: 0.114, green: 0.62, blue: 0.459)

    init(style: Style = .full, title: String = "") {
        self.style = style
        self.title = title
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let safeTop = geo.safeAreaInsets.top

            ZStack(alignment: .bottomTrailing) {
                // Diagonal gradient
                LinearGradient(
                    colors: [darkGreen, Self.bannerColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Turf stripes
                turfStripes(width: w, height: h)

                // Center circle + line on right side
                pitchMarkings(width: w, height: h)

                // Shimmer
                shimmerOverlay(width: w)

                // Text content
                if style == .full {
                    fullContent(safeTop: safeTop)
                } else {
                    compactContent(safeTop: safeTop)
                }
            }
        }
        .frame(height: style == .full ? 140 : 88)
        .frame(maxWidth: .infinity)
        .clipped()
        .ignoresSafeArea(edges: .top)
        .onAppear { startAnimations() }
    }

    // MARK: - Turf Stripes

    private func turfStripes(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            let stripeWidth: CGFloat = 46
            var x: CGFloat = 0
            var even = true
            while x < width {
                if even {
                    let rect = CGRect(x: x, y: 0, width: stripeWidth, height: height)
                    context.fill(Path(rect), with: .color(.white.opacity(0.06)))
                }
                x += stripeWidth
                even.toggle()
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Pitch Markings (right side)

    private func pitchMarkings(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            let centerX = width * 0.84
            let centerY = height * 0.5
            let circleR: CGFloat = style == .full ? 48 : 32
            let opacity = glowOpacity

            // Center line
            var line = Path()
            line.move(to: CGPoint(x: centerX, y: 0))
            line.addLine(to: CGPoint(x: centerX, y: height))
            context.stroke(line, with: .color(lineColor), lineWidth: 1.5)

            // Center circle
            let circleRect = CGRect(
                x: centerX - circleR, y: centerY - circleR,
                width: circleR * 2, height: circleR * 2
            )
            context.stroke(
                Path(ellipseIn: circleRect),
                with: .color(.white.opacity(opacity + 0.06)),
                lineWidth: 1.5
            )

            // Center dot
            let dotR: CGFloat = 2.5
            context.fill(
                Path(ellipseIn: CGRect(x: centerX - dotR, y: centerY - dotR, width: dotR * 2, height: dotR * 2)),
                with: .color(.white.opacity(0.35))
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Content

    private func fullContent(safeTop: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Spacer()
            HStack(spacing: 6) {
                Text("\u{26bd}")
                    .font(.system(size: 16))
                    .rotationEffect(.degrees(ballRotation))
                    .opacity(ballOpacity)
                    .offset(y: ballOffset)
                Text(title.isEmpty ? "MatchMondo" : title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                if data.anyLive {
                    liveBadge
                }
            }
            Text("Football 2026 \u{00b7} June 11 \u{2013} July 19 \u{00b7} USA, Canada & Mexico \u{00b7} \(data.playedCount) of \(data.totalCount) matches played")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 20)
        .padding(.bottom, 14)
    }

    private func compactContent(safeTop: CGFloat) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Text("\u{26bd}")
                    .font(.system(size: 13))
                    .rotationEffect(.degrees(ballRotation))
                    .opacity(ballOpacity)
                    .offset(y: ballOffset)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                if data.anyLive {
                    liveBadge
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 20)
        .padding(.bottom, 10)
    }

    private var liveBadge: some View {
        Text("LIVE")
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red)
            .clipShape(Capsule())
    }

    // MARK: - Shimmer

    private func shimmerOverlay(width: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.06), .white.opacity(0.12), .white.opacity(0.06), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width * 0.6)
            .offset(x: shimmerPhase * width * 1.3)
            .opacity(shimmerOpacity)
            .allowsHitTesting(false)
            .clipped()
    }

    // MARK: - Animations

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: false)) {
            shimmerPhase = 1
        }

        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            glowOpacity = 0.3
        }

        let bounceHeights: [CGFloat] = [-16, -10, -5]
        let stepDur = 0.25

        var delay = 0.0
        for height in bounceHeights {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.linear(duration: stepDur)) {
                    ballOffset = height
                    ballRotation += 180
                }
            }
            delay += stepDur
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.linear(duration: stepDur)) {
                    ballOffset = 0
                    ballRotation += 180
                }
            }
            delay += stepDur
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.6)) {
                ballOpacity = 0.15
                shimmerOpacity = 0
            }
        }
    }
}
