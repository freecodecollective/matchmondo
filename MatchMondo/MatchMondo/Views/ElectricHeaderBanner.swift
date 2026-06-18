import SwiftUI

struct ElectricHeaderBanner: View {
    @EnvironmentObject var data: DataService

    @State private var shimmerPhase: CGFloat = -1
    @State private var ballPosition = CGPoint(x: 0.12, y: 0.28)
    @State private var ballRotation: Double = 0
    @State private var ballOpacity: Double = 0.7
    @State private var glowOpacity: Double = 0.12

    private let darkGreen = Color(red: 0.02, green: 0.082, blue: 0.067)
    private let midGreen = Color(red: 0.031, green: 0.165, blue: 0.11)
    private let pitchLineColor = Color(red: 0.114, green: 0.62, blue: 0.459)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [darkGreen, midGreen, Color(red: 0.043, green: 0.239, blue: 0.157)],
                startPoint: .top,
                endPoint: .bottom
            )

            pitchLines
            shimmerOverlay
            bouncingBall

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("Football 2026")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: pitchLineColor.opacity(0.4), radius: 8)
                    if data.anyLive {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
                Text("June 11 \u{2013} July 19 \u{00b7} USA, Canada & Mexico")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                Text("\(data.playedCount) of \(data.totalCount) matches played")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .clipped()
        .onAppear {
            startAnimations()
        }
    }

    private var pitchLines: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Canvas { context, size in
                let lineColor = pitchLineColor.opacity(0.15)
                let glowColor = pitchLineColor.opacity(glowOpacity)

                // Outer border
                let border = CGRect(x: 10, y: 8, width: w - 20, height: h - 16)
                context.stroke(Path(border), with: .color(lineColor), lineWidth: 1.5)

                // Center line
                var centerLine = Path()
                centerLine.move(to: CGPoint(x: w / 2, y: 8))
                centerLine.addLine(to: CGPoint(x: w / 2, y: h - 8))
                context.stroke(centerLine, with: .color(glowColor), lineWidth: 1.5)

                // Center circle
                let circleR: CGFloat = 32
                let circleRect = CGRect(x: w / 2 - circleR, y: h / 2 - circleR, width: circleR * 2, height: circleR * 2)
                context.stroke(Path(ellipseIn: circleRect), with: .color(glowColor), lineWidth: 1.5)

                // Center dot
                let dotR: CGFloat = 2
                context.fill(Path(ellipseIn: CGRect(x: w / 2 - dotR, y: h / 2 - dotR, width: dotR * 2, height: dotR * 2)),
                             with: .color(pitchLineColor.opacity(0.35)))

                // Left penalty box
                let leftBox = CGRect(x: 10, y: h * 0.25, width: w * 0.12, height: h * 0.5)
                context.stroke(Path(leftBox), with: .color(lineColor), lineWidth: 1)

                // Right penalty box
                let rightBox = CGRect(x: w - 10 - w * 0.12, y: h * 0.25, width: w * 0.12, height: h * 0.5)
                context.stroke(Path(rightBox), with: .color(lineColor), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private var shimmerOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.06), .white.opacity(0.12), .white.opacity(0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: w * 0.6)
                .offset(x: shimmerPhase * w * 1.3)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    private var bouncingBall: some View {
        GeometryReader { geo in
            Text("⚽")
                .font(.system(size: 16))
                .rotationEffect(.degrees(ballRotation))
                .opacity(ballOpacity)
                .shadow(color: pitchLineColor.opacity(0.5), radius: 8)
                .position(
                    x: ballPosition.x * geo.size.width,
                    y: ballPosition.y * geo.size.height
                )
                .allowsHitTesting(false)
        }
    }

    private func startAnimations() {
        // Shimmer: continuous loop
        withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: false)) {
            shimmerPhase = 1
        }

        // Glow pulse: continuous
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            glowOpacity = 0.3
        }

        // Ball bounce: 3-second animation then stop
        let positions: [(CGPoint, Double)] = [
            (CGPoint(x: 0.12, y: 0.28), 0),
            (CGPoint(x: 0.30, y: 0.65), 180),
            (CGPoint(x: 0.50, y: 0.30), 360),
            (CGPoint(x: 0.70, y: 0.70), 540),
            (CGPoint(x: 0.85, y: 0.35), 720),
            (CGPoint(x: 0.75, y: 0.60), 900),
            (CGPoint(x: 0.55, y: 0.25), 1080),
        ]

        let stepDuration = 3.0 / Double(positions.count - 1)

        for i in 1..<positions.count {
            let delay = stepDuration * Double(i)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: stepDuration)) {
                    ballPosition = positions[i].0
                    ballRotation = positions[i].1
                }
            }
        }

        // Fade ball out at the end
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.8)) {
                ballOpacity = 0.2
            }
        }
    }
}
