//
//  SystemStatsView.swift
//  boringNotch
//

import SwiftUI

struct SystemStatsView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var monitor = SystemStatsMonitor.shared
    @ObservedObject private var thermalDetailMonitor = ThermalDetailMonitor.shared
    @State private var isThermalDetailsExpanded = false

    private var snapshot: SystemStatsSnapshot {
        monitor.snapshot
    }

    private var thermalSnapshot: ThermalDetailSnapshot {
        thermalDetailMonitor.snapshot
    }

    private var currentNotchHeight: CGFloat {
        isThermalDetailsExpanded ? expandedThermalNotchHeight : openNotchSize.height
    }

    var body: some View {
        VStack(spacing: 8) {
            SystemGraphRow(
                title: "cpu",
                currentValue: snapshot.cpuUsage,
                samples: snapshot.cpuHistory,
                valueRange: 0...1,
                valueStyle: .percentage,
                color: Color(red: 0.42, green: 0.72, blue: 1.0)
            )

            SystemGraphRow(
                title: "ram",
                currentValue: snapshot.memoryUsage,
                samples: snapshot.memoryHistory,
                valueRange: 0...1,
                valueStyle: .percentage,
                color: Color(red: 0.35, green: 0.86, blue: 0.61)
            )

            VStack(spacing: 6) {
                SystemGraphRow(
                    title: "temp",
                    currentValue: snapshot.temperatureCelsius,
                    samples: snapshot.temperatureHistory,
                    valueRange: 30...100,
                    valueStyle: .temperature,
                    color: Color(red: 1.0, green: 0.62, blue: 0.26),
                    isExpandable: true,
                    isExpanded: isThermalDetailsExpanded,
                    onTitleTap: toggleThermalDetails
                )

                if isThermalDetailsExpanded {
                    ThermalDetailsPanel(snapshot: thermalSnapshot)
                        .transition(
                            .asymmetric(
                                insertion: .offset(y: -8).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                                removal: .offset(y: -4).combined(with: .opacity)
                            )
                        )
                }
            }
        }
        .frame(width: 574)
        .padding(.top, 2)
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
        .animation(.smooth(duration: 0.85), value: snapshot.cpuHistory)
        .animation(.smooth(duration: 0.85), value: snapshot.memoryHistory)
        .animation(.smooth(duration: 0.85), value: snapshot.temperatureHistory)
        .animation(.interactiveSpring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.08), value: isThermalDetailsExpanded)
        .onChange(of: isThermalDetailsExpanded) { _, isExpanded in
            thermalDetailMonitor.setExpanded(isExpanded)
            vm.setOpenHeight(isExpanded ? expandedThermalNotchHeight : openNotchSize.height)
        }
        .onAppear {
            vm.setOpenHeight(currentNotchHeight)
        }
        .onDisappear {
            isThermalDetailsExpanded = false
            thermalDetailMonitor.setExpanded(false)
            vm.resetOpenHeight()
        }
    }

    private func toggleThermalDetails() {
        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.08)) {
            isThermalDetailsExpanded.toggle()
        }
    }
}

private struct SystemGraphRow: View {
    let title: String
    let currentValue: Double?
    let samples: [Double]
    let valueRange: ClosedRange<Double>
    let valueStyle: SystemGraphValueStyle
    let color: Color
    var isExpandable: Bool = false
    var isExpanded: Bool = false
    var onTitleTap: (() -> Void)?

    @State private var hoveredValue: Double?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                titleView

                Text(valueText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .frame(width: 58, alignment: .leading)

            SmoothSparklineGraph(
                samples: samples,
                valueRange: valueRange,
                color: color,
                hoveredValue: $hoveredValue
            )
        }
        .padding(.horizontal, 12)
        .frame(width: 574, height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.12),
                            Color.white.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.32), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: color.opacity(0.13), radius: 10, y: 4)
    }

    @ViewBuilder
    private var titleView: some View {
        if let onTitleTap {
            Button(action: onTitleTap) {
                HStack(spacing: 4) {
                    Text(title)
                    if isExpandable {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .foregroundStyle(.white.opacity(0.72))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(title)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var valueText: String {
        valueStyle.text(for: hoveredValue ?? currentValue)
    }
}

private struct ThermalDetailsPanel: View {
    let snapshot: ThermalDetailSnapshot

    var body: some View {
        HStack(spacing: 10) {
            ThermalDetailMetric(
                title: "hottest cpu",
                value: valueText(snapshot.hottestCPUCelsius)
            )

            ThermalDetailMetric(
                title: "battery",
                value: valueText(snapshot.batteryCelsius)
            )
        }
        .padding(.horizontal, 12)
        .frame(width: 574)
        .padding(.top, 2)
        .clipped()
    }

    private func valueText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1fC", value)
    }
}

private struct ThermalDetailMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SmoothSparklineGraph: View {
    let samples: [Double]
    let valueRange: ClosedRange<Double>
    let color: Color
    @Binding var hoveredValue: Double?

    private var graphSamples: [Double] {
        if samples.count >= 2 {
            return samples
        }

        let fallback = samples.first ?? valueRange.lowerBound
        return [fallback, fallback]
    }

    private var displayRange: ClosedRange<Double> {
        let values = graphSamples
        guard let minValue = values.min(), let maxValue = values.max() else {
            return valueRange
        }

        let fullSpan = valueRange.upperBound - valueRange.lowerBound
        let minimumVisibleSpan = max(fullSpan * 0.18, fullSpan > 2 ? 4 : 0.08)
        let rawSpan = max(maxValue - minValue, minimumVisibleSpan)
        let padding = rawSpan * 0.22

        let lower = max(valueRange.lowerBound, minValue - padding)
        let upper = min(valueRange.upperBound, maxValue + padding)

        if upper - lower >= minimumVisibleSpan {
            return lower...upper
        }

        let center = (minValue + maxValue) * 0.5
        let halfSpan = minimumVisibleSpan * 0.5
        return max(valueRange.lowerBound, center - halfSpan)...min(valueRange.upperBound, center + halfSpan)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let line = smoothPath(in: size)

            ZStack(alignment: .leading) {
                grid(in: size)

                fillPath(from: line, in: size)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.28), color.opacity(0.015)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                line
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.55), color, color.opacity(0.78)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: color.opacity(0.58), radius: 4)

                if let selected = selectedSample(in: size) {
                    Path { path in
                        path.move(to: CGPoint(x: selected.point.x, y: 0))
                        path.addLine(to: CGPoint(x: selected.point.x, y: size.height))
                    }
                    .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

                    Circle()
                        .fill(.black)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle()
                                .stroke(color, lineWidth: 2)
                        }
                        .position(selected.point)
                        .shadow(color: color.opacity(0.7), radius: 4)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hoveredValue = nearestValue(for: value.location.x, width: size.width)
                    }
                    .onEnded { _ in
                        hoveredValue = nil
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredValue = nearestValue(for: location.x, width: size.width)
                case .ended:
                    hoveredValue = nil
                }
            }
        }
        .frame(height: 30)
        .clipped()
        .drawingGroup()
    }

    private func grid(in size: CGSize) -> some View {
        Path { path in
            let midY = size.height * 0.5
            path.move(to: CGPoint(x: 0, y: midY))
            path.addLine(to: CGPoint(x: size.width, y: midY))
        }
        .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
    }

    private func smoothPath(in size: CGSize) -> Path {
        let points = points(in: size)
        var path = Path()

        guard let first = points.first else { return path }
        path.move(to: first)

        guard points.count > 1 else { return path }

        for index in 0..<(points.count - 1) {
            let previous = points[max(index - 1, 0)]
            let current = points[index]
            let next = points[index + 1]
            let nextNext = points[min(index + 2, points.count - 1)]

            let control1 = CGPoint(
                x: current.x + (next.x - previous.x) / 6,
                y: current.y + (next.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: next.x - (nextNext.x - current.x) / 6,
                y: next.y - (nextNext.y - current.y) / 6
            )

            path.addCurve(to: next, control1: control1, control2: control2)
        }

        return path
    }

    private func fillPath(from linePath: Path, in size: CGSize) -> Path {
        var path = linePath
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let verticalInset: CGFloat = 1
        let graphHeight = max(size.height - (verticalInset * 2), 1)
        let values = graphSamples.map(normalizedValue)
        let step = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0

        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: verticalInset + ((1 - CGFloat(value)) * graphHeight)
            )
        }
    }

    private func selectedSample(in size: CGSize) -> (value: Double, point: CGPoint)? {
        guard let hoveredValue else { return nil }
        let values = graphSamples
        guard let index = values.enumerated().min(by: { abs($0.element - hoveredValue) < abs($1.element - hoveredValue) })?.offset else {
            return nil
        }

        let point = points(in: size)[index]
        return (values[index], point)
    }

    private func nearestValue(for x: CGFloat, width: CGFloat) -> Double? {
        let values = graphSamples
        guard !values.isEmpty, width > 0 else { return nil }

        let clampedX = min(max(x, 0), width)
        let progress = clampedX / width
        let index = min(max(Int((progress * CGFloat(values.count - 1)).rounded()), 0), values.count - 1)
        return values[index]
    }

    private func normalizedValue(_ value: Double) -> Double {
        let span = displayRange.upperBound - displayRange.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - displayRange.lowerBound) / span, 0), 1)
    }
}

private enum SystemGraphValueStyle {
    case percentage
    case temperature

    func text(for value: Double?) -> String {
        guard let value else { return "--" }

        switch self {
        case .percentage:
            return "\(Int((value * 100).rounded()))%"
        case .temperature:
            return "\(Int(value.rounded()))C"
        }
    }
}

private struct SystemStatsViewPreviewContainer: View {
    var body: some View {
        SystemStatsView()
            .environmentObject(BoringViewModel())
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black)
            )
            .frame(width: 640, height: 190)
    }
}

#if !SWIFT_PACKAGE
#Preview {
    SystemStatsViewPreviewContainer()
}
#endif
