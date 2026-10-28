import SwiftUI

struct ProgressRingView: View {
    let progress: Double
    let color: Color
    let isPaused: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 10)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isPaused ? Color.secondary : color,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
        .frame(width: 220, height: 220)
        .accessibilityHidden(true)
    }
}
