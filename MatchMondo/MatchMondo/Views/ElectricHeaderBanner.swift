import SwiftUI

struct ElectricHeaderBanner: View {
    enum Style { case full, compact }

    let style: Style
    @EnvironmentObject var data: DataService

    @State private var shimmerPhase: CGFloat = -1
    @State private var shimmerOpacity: Double = 1.0
    @State private var ballY: CGFloat = 0.7
    @State private var ballRotation: Double = 0
    @State private var ballOpacity: Double = 0.7
    @State private var glowOpacity: Double = 0.12

    private let darkGreen = Color(red: 0.02, green: 0.082, blue: 0.067)
    private let midGreen = Color(red: 0.031, green: 0.165, blue: 0.11)
    private let pitchLineColor = Color(red: 0.114, green: 0.62, blue: 0.459)

    init(style: Style = .full) {
        self.style = style
    }

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

            if style == .full {
                VStack(spacing: 4) {
                    Spacer()
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
                        .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: style == .full ? 120 : 44)
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

                let border = CGRect(x: 10, y: 8, width: w - 20, height: h - 16)
                context.stroke(Path(border), with: .color(lineColor), lineWidth: 1.5)

                var centerLine = Path()
                centerLine.move(to: CGPoint(x: w / 2, y: 8))
                centerLine.addLine(to: CGPoint(x: w / 2, y: h - 8))
                context.stroke(centerLine, with: .color(glowColor), lineWidth: 1.5)

                let circleR: CGFloat = style == .full ? 32 : 18
                let circleRect = CGRect(x: w / 2 - circleR, y: h / 2 - circleR, width: circleR * 2, height: circleR * 2)
                context.stroke(Path(ellipseIn: circleRect), with: .color(glowColor), lineWidth: 1.5)

                let dotR: CGFloat = 2
                context.fill(Path(ellipseIn: CGRect(x: w / 2 - dotR, y: h / 2 - dotR, width: dotR * 2, height: dotR * 2)),
                             with: .color(pitchLineColor.opacity(0.35)))

                let boxH = h * 0.5
                let boxW = w * 0.12
                let leftBox = CGRect(x: 10, y: h * 0.25, width: boxW, height: boxH)
                context.stroke(Path(leftBox), with: .color(lineColor), lineWidth: 1)

                let rightBox = CGRect(x: w - 10 - boxW, y: h * 0.25, width: boxW, height: boxH)
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
                .opacity(shimmerOpacity)
                .allowsHitTesting(false)
        }
        .clipped()
    }

    private var bouncingBall: some View {
        GeometryReader { geo in
            let ballX = style == .full ? 0.5 : 0.5
            Text("⚽")
                .font(.system(size: style == .full ? 16 : 12))
                .rotationEffect(.degrees(ballRotation))
                .opacity(ballOpacity)
                .shadow(color: pitchLineColor.opacity(0.5), radius: 8)
                .position(
                    x: ballX * geo.size.width,
                    y: ballY * geo.size.height
                )
                .allowsHitTesting(false)
        }
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: false)) {
            shimmerPhase = 1
        }

        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            glowOpacity = 0.3
        }

        // Ball: 3 bounces with decreasing height, linear speed
        let ground: CGFloat = 0.7
        let heights: [CGFloat] = [0.2, 0.35, 0.5]
        let stepDur = 0.3

        var delay = 0.0
        for peak in heights {
            // Go up
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.linear(duration: stepDur)) {
                    ballY = peak
                    ballRotation += 180
                }
            }
            delay += stepDur
            // Come down
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.linear(duration: stepDur)) {
                    ballY = ground
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
