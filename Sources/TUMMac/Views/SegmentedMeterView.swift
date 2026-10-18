import SwiftUI

struct SegmentedMeterView: View {
    let fractionRemaining: Double
    let color: Color
    var segments: Int = 28

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(segments - 1)
            let width = max((geo.size.width - totalSpacing) / CGFloat(segments), 1)
            let filled = Int((fractionRemaining * Double(segments)).rounded())

            HStack(spacing: spacing) {
                ForEach(0..<segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(index < filled ? color : color.opacity(0.18))
                        .frame(width: width, height: 8)
                }
            }
        }
        .frame(height: 8)
        .accessibilityLabel("\(Int((fractionRemaining * 100).rounded())) percent left")
    }
}
