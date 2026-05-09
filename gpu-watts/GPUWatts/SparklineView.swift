import SwiftUI

struct SparklineView: View {
    let values: [Int]
    let height: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            if values.isEmpty {
                Rectangle().fill(Color.gray.opacity(0.3))
            } else {
                Path { path in
                    let minVal = values.min() ?? 0
                    let maxVal = values.max() ?? 0
                    let range = max(maxVal - minVal, 1) // avoid division by zero

                    let width = geo.size.width
                    let height = geo.size.height
                    let step = width / CGFloat(values.count - 1)

                    for (i, value) in values.enumerated() {
                        let x = CGFloat(i) * step
                        let normalizedY = CGFloat(value - minVal) / CGFloat(range)
                        let y = height - normalizedY * (height - 4) - 2 // 2px padding

                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
        .frame(height: height)
    }
}
