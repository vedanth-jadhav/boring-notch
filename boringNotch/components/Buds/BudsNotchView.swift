import SwiftUI

struct BudsNotchView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var model = BudsAppModel.shared

    var body: some View {
        HStack(spacing: 12) {
            BudsHero(model: model)
                .frame(width: 176)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    BudsBatteryReadout(kind: .left, value: model.battery?.left)
                    BudsBatteryReadout(kind: .right, value: model.battery?.right)
                    BudsBatteryReadout(kind: .case, value: model.displayBattery?.case)
                }
                .frame(height: 58)

                BudsNoiseCapsule(model: model)
                    .frame(height: 46)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 574, height: 134)
        .background(BudsGlassPanel())
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
        .onAppear { model.onViewAppear() }
        .onDisappear { model.onViewDisappear() }
    }
}

private enum BudsUI {
    static let spring = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.04)
    static let green = Color(red: 0.16, green: 0.92, blue: 0.27)
    static let amber = Color(red: 1.0, green: 0.74, blue: 0.22)
    static let red = Color(red: 1.0, green: 0.22, blue: 0.20)
    static let cardFill = Color.white.opacity(0.075)
    static let cardStroke = Color.white.opacity(0.13)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.54)
}

private struct BudsHero: View {
    @ObservedObject var model: BudsAppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.11),
                            Color(red: 0.08, green: 0.09, blue: 0.11).opacity(0.64),
                            Color.black.opacity(0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(BudsUI.cardStroke, lineWidth: 1))

            RadialGradient(
                colors: [BudsUI.green.opacity(model.shouldShowTab ? 0.24 : 0.08), .clear],
                center: .bottom,
                startRadius: 6,
                endRadius: 126
            )

            Image("budsProduct")
                .resizable()
                .scaledToFit()
                .frame(width: 174, height: 112)
                .offset(x: 2, y: 28)
                .shadow(color: .black.opacity(0.72), radius: 12, y: 7)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(BudsUI.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.shouldShowTab ? BudsUI.green : .white.opacity(0.30))
                            .frame(width: 7, height: 7)
                            .shadow(color: model.shouldShowTab ? BudsUI.green.opacity(0.72) : .clear, radius: 4)

                        Text(statusText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(BudsUI.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }

                    if model.isConnected {
                        Text("🎧")
                            .font(.system(size: 17))
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName), \(statusText)")
    }

    private var displayName: String {
        let name = model.connectedDeviceName
            .replacingOccurrences(of: "OnePlus ", with: "")
            .replacingOccurrences(of: "Nord ", with: "")
        return name == "Buds" ? "Buds Pro" : name
    }

    private var statusText: String {
        model.isConnected ? "Connected" : model.connectionSubtitle
    }
}

private struct BudsBatteryReadout: View {
    enum Kind {
        case left
        case right
        case `case`

        var label: String {
            switch self {
            case .left: "Left"
            case .right: "Right"
            case .case: "Case"
            }
        }

        var shortLabel: String {
            switch self {
            case .left: "L"
            case .right: "R"
            case .case: "Case"
            }
        }
    }

    let kind: Kind
    let value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                BudsBatteryIcon(kind: kind)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(iconColor)

                Text(kind.shortLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(BudsUI.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Text(valueText)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value == nil ? .white.opacity(0.42) : BudsUI.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            BudsBatteryBar(value: value)
                .frame(height: 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(BudsUI.cardFill)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(BudsUI.cardStroke, lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.label) battery \(valueText)")
    }

    private var valueText: String {
        value.map { "\($0)%" } ?? "--"
    }

    private var iconColor: Color {
        guard let value else { return .white.opacity(0.52) }
        switch value {
        case 0..<20: return BudsUI.red
        case 20..<55: return BudsUI.amber
        default: return BudsUI.green
        }
    }
}

private struct BudsBatteryBar: View {
    let value: Int?

    var body: some View {
        GeometryReader { geometry in
            let progress = CGFloat(max(0, min(value ?? 0, 100))) / 100

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.13))

                Capsule()
                    .fill(fillColor)
                    .frame(width: geometry.size.width * progress)
                    .opacity(value == nil ? 0 : 1)
            }
        }
    }

    private var fillColor: Color {
        guard let value else { return .clear }
        switch value {
        case 0..<20: return BudsUI.red
        case 20..<55: return BudsUI.amber
        default: return BudsUI.green
        }
    }
}

private struct BudsNoiseCapsule: View {
    @ObservedObject var model: BudsAppModel

    var body: some View {
        if model.isConnected {
            HStack(spacing: 4) {
                BudsModeSegment(
                    mode: .off,
                    title: "Off",
                    icon: .off,
                    selection: model.anc,
                    action: model.setANC
                )

                BudsModeSegment(
                    mode: .on,
                    title: "ANC",
                    icon: .anc,
                    selection: model.anc,
                    action: model.setANC
                )

                BudsModeSegment(
                    mode: .transparency,
                    title: "Aware",
                    icon: .transparency,
                    selection: model.anc,
                    action: model.setANC
                )
            }
            .padding(4)
            .background {
                Capsule()
                    .fill(.black.opacity(0.28))
                    .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
            }
        } else {
            Button(action: model.reconnect) {
                HStack(spacing: 10) {
                    BudsModeIcon(.sync, active: false)
                        .frame(width: 24, height: 24)

                    Text(model.connectionSubtitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Capsule()
                        .fill(.black.opacity(0.28))
                        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                }
            }
            .buttonStyle(BudsPressButtonStyle())
            .accessibilityLabel("Reconnect Buds")
        }
    }
}

private struct BudsModeSegment: View {
    let mode: ANCMode
    let title: String
    let icon: BudsModeIcon.Kind
    let selection: ANCMode?
    let action: (ANCMode) -> Void

    @State private var optimisticSelection: ANCMode?
    @State private var optimisticClearTask: Task<Void, Never>?

    private var isSelected: Bool {
        (optimisticSelection ?? selection) == mode
    }

    var body: some View {
        Button {
            selectMode()
        } label: {
            HStack(spacing: 7) {
                BudsModeIcon(icon, active: isSelected)
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Capsule()
                    .fill(isSelected ? .white.opacity(0.115) : .clear)
                    .overlay(Capsule().stroke(isSelected ? .white.opacity(0.30) : .clear, lineWidth: 1))
                    .shadow(color: isSelected ? .white.opacity(0.11) : .clear, radius: 14, y: 1)
            }
        }
        .buttonStyle(BudsPressButtonStyle())
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(BudsUI.spring, value: isSelected)
        .onChange(of: selection) { _, _ in
            optimisticClearTask?.cancel()
            optimisticClearTask = nil
            optimisticSelection = nil
        }
        .onDisappear {
            optimisticClearTask?.cancel()
            optimisticClearTask = nil
        }
    }

    private func selectMode() {
        guard selection != mode else { return }
        optimisticSelection = mode
        optimisticClearTask?.cancel()
        optimisticClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if optimisticSelection == mode {
                optimisticSelection = nil
            }
        }
        action(mode)
    }

    private var accessibilityTitle: String {
        switch mode {
        case .on: "Noise Cancellation"
        case .transparency: "Transparency"
        case .off: "Noise Control Off"
        }
    }
}

private struct BudsGlassPanel: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(.black.opacity(0.78))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.12), .white.opacity(0.025), .clear],
                            center: .topLeading,
                            startRadius: 8,
                            endRadius: 520
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct BudsPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(BudsUI.spring, value: configuration.isPressed)
    }
}

private struct BudsBatteryIcon: View {
    let kind: BudsBatteryReadout.Kind

    var body: some View {
        Canvas { context, size in
            let line = min(size.width, size.height) * 0.095
            let stroke = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)

            var path = Path()
            switch kind {
            case .left, .right:
                let letter = kind == .left ? "L" : "R"
                path.addEllipse(in: CGRect(x: size.width * 0.12, y: size.height * 0.12, width: size.width * 0.76, height: size.height * 0.76))
                context.stroke(path, with: .foreground, style: stroke)
                let text = Text(letter).font(.system(size: size.height * 0.50, weight: .semibold, design: .rounded))
                context.draw(text, at: CGPoint(x: size.width * 0.5, y: size.height * 0.50), anchor: .center)

            case .case:
                path.addRoundedRect(in: CGRect(x: size.width * 0.10, y: size.height * 0.22, width: size.width * 0.80, height: size.height * 0.54), cornerSize: CGSize(width: size.width * 0.16, height: size.height * 0.16))
                path.move(to: CGPoint(x: size.width * 0.34, y: size.height * 0.28))
                path.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.28))
                path.move(to: CGPoint(x: size.width * 0.43, y: size.height * 0.49))
                path.addLine(to: CGPoint(x: size.width * 0.57, y: size.height * 0.49))
                context.stroke(path, with: .foreground, style: stroke)
            }
        }
    }
}

private struct BudsModeIcon: View {
    enum Kind {
        case off
        case transparency
        case anc
        case sync
    }

    let kind: Kind
    let active: Bool

    init(_ kind: Kind, active: Bool) {
        self.kind = kind
        self.active = active
    }

    var body: some View {
        Canvas { context, size in
            let line = min(size.width, size.height) * 0.075
            let foreground = active ? Color.white.opacity(0.95) : Color.white.opacity(0.58)
            let stroke = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)

            func strokePath(_ build: (inout Path) -> Void) {
                var path = Path()
                build(&path)
                context.stroke(path, with: .color(foreground), style: stroke)
            }

            switch kind {
            case .off:
                strokePath { path in
                    path.addArc(center: CGPoint(x: size.width * 0.5, y: size.height * 0.5), radius: size.width * 0.34, startAngle: .degrees(22), endAngle: .degrees(158), clockwise: false)
                    path.addArc(center: CGPoint(x: size.width * 0.5, y: size.height * 0.5), radius: size.width * 0.34, startAngle: .degrees(202), endAngle: .degrees(338), clockwise: false)
                }

            case .transparency:
                let dotCount = 18
                for index in 0..<dotCount {
                    let angle = (Double(index) / Double(dotCount)) * .pi * 2
                    let point = CGPoint(
                        x: size.width * 0.5 + cos(angle) * size.width * 0.33,
                        y: size.height * 0.5 + sin(angle) * size.height * 0.33
                    )
                    var dot = Path()
                    dot.addEllipse(in: CGRect(x: point.x - line * 0.62, y: point.y - line * 0.62, width: line * 1.24, height: line * 1.24))
                    context.fill(dot, with: .color(foreground))
                }
                strokePath { path in
                    path.addArc(center: CGPoint(x: size.width * 0.42, y: size.height * 0.5), radius: size.width * 0.13, startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false)
                    path.addArc(center: CGPoint(x: size.width * 0.41, y: size.height * 0.5), radius: size.width * 0.23, startAngle: .degrees(-42), endAngle: .degrees(42), clockwise: false)
                }

            case .anc:
                strokePath { path in
                    path.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.10))
                    path.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.22))
                    path.addLine(to: CGPoint(x: size.width * 0.76, y: size.height * 0.62))
                    path.addCurve(to: CGPoint(x: size.width * 0.5, y: size.height * 0.90), control1: CGPoint(x: size.width * 0.70, y: size.height * 0.76), control2: CGPoint(x: size.width * 0.58, y: size.height * 0.84))
                    path.addCurve(to: CGPoint(x: size.width * 0.24, y: size.height * 0.62), control1: CGPoint(x: size.width * 0.42, y: size.height * 0.84), control2: CGPoint(x: size.width * 0.30, y: size.height * 0.76))
                    path.addLine(to: CGPoint(x: size.width * 0.22, y: size.height * 0.22))
                    path.closeSubpath()
                    path.move(to: CGPoint(x: size.width * 0.34, y: size.height * 0.55))
                    path.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.45))
                    path.move(to: CGPoint(x: size.width * 0.43, y: size.height * 0.66))
                    path.addLine(to: CGPoint(x: size.width * 0.43, y: size.height * 0.34))
                    path.move(to: CGPoint(x: size.width * 0.52, y: size.height * 0.72))
                    path.addLine(to: CGPoint(x: size.width * 0.52, y: size.height * 0.28))
                    path.move(to: CGPoint(x: size.width * 0.61, y: size.height * 0.62))
                    path.addLine(to: CGPoint(x: size.width * 0.61, y: size.height * 0.38))
                    path.move(to: CGPoint(x: size.width * 0.70, y: size.height * 0.54))
                    path.addLine(to: CGPoint(x: size.width * 0.70, y: size.height * 0.46))
                }

            case .sync:
                strokePath { path in
                    path.addArc(center: CGPoint(x: size.width * 0.5, y: size.height * 0.5), radius: size.width * 0.31, startAngle: .degrees(30), endAngle: .degrees(330), clockwise: false)
                    path.move(to: CGPoint(x: size.width * 0.76, y: size.height * 0.25))
                    path.addLine(to: CGPoint(x: size.width * 0.88, y: size.height * 0.29))
                    path.addLine(to: CGPoint(x: size.width * 0.79, y: size.height * 0.40))
                }
            }
        }
        .shadow(color: active ? .white.opacity(0.40) : .clear, radius: 5)
    }
}
