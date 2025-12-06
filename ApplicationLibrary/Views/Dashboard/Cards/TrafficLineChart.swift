import SwiftUI

public struct TrafficLineChart: View {
    private let data: [CGFloat]
    private let lineColor: Color
    private let gridColor: Color
    private let chartHeight: CGFloat

    public init(
        data: [CGFloat],
        lineColor: Color = .primary,
        gridColor: Color = Color.secondary.opacity(0.3),
        chartHeight: CGFloat = 60
    ) {
        self.data = data
        self.lineColor = lineColor
        self.gridColor = gridColor
        self.chartHeight = chartHeight
    }

    public var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let maxValue = max((data.max() ?? 1) * 1.2, 1)
            let pointCount = data.count

            drawGrid(context: context, width: width, height: height)

            guard pointCount > 1 else { return }

            let spacing = width / CGFloat(pointCount - 1)
            let points = data.enumerated().map { index, value in
                let x = CGFloat(index) * spacing
                let normalizedValue = min(max(value / maxValue, 0), 1)
                let y = height * (1 - normalizedValue)
                return CGPoint(x: x, y: y)
            }

            drawLine(context: context, points: points, height: height)
        }
        .frame(height: chartHeight)
    }

    private func drawGrid(context: GraphicsContext, width: CGFloat, height: CGFloat) {
        let gridLineCount = 3
        for i in 0 ... gridLineCount {
            let y = height * CGFloat(i) / CGFloat(gridLineCount)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
            context.stroke(
                path,
                with: .color(gridColor),
                style: StrokeStyle(lineWidth: 1, dash: [5, 5])
            )
        }
    }

    private func drawLine(context: GraphicsContext, points: [CGPoint], height: CGFloat) {
        guard !points.isEmpty else { return }

        var linePath = Path()
        linePath.move(to: points[0])
        for point in points.dropFirst() {
            linePath.addLine(to: point)
        }

        context.stroke(
            linePath,
            with: .color(lineColor),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        var fillPath = linePath
        if let lastPoint = points.last {
            fillPath.addLine(to: CGPoint(x: lastPoint.x, y: height))
            fillPath.addLine(to: CGPoint(x: 0, y: height))
            fillPath.addLine(to: points[0])
        }

        context.fill(fillPath, with: .color(lineColor.opacity(0.1)))
    }
}
