//
//  LockScreenPanelControlButton.swift
//  boringNotch
//

import SwiftUI

struct LockScreenPanelControlButton: View {
    let label: String
    let icon: String
    let frameSize: CGFloat
    let iconSize: CGFloat
    let iconColor: Color
    let backgroundOpacity: Double
    let interaction: Interaction
    let symbolEffect: SymbolEffectStyle
    let action: () -> Void

    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var wiggleToken = 0

    var body: some View {
        Button(label, systemImage: icon) {
            action()
            triggerPressEffect()
        }
        .labelStyle(.iconOnly)
        .font(.system(size: iconSize, weight: .medium))
        .foregroundStyle(iconColor)
        .contentTransition(contentTransition)
        .frame(width: frameSize, height: frameSize)
        .background {
            RoundedRectangle(cornerRadius: frameSize / 2, style: .continuous)
                .fill(backgroundColor)
        }
        .buttonStyle(.plain)
        .offset(x: pressOffset)
        .rotationEffect(.degrees(rotationAngle))
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(label)
    }

    private var backgroundColor: Color {
        let hoveredOpacity = max(backgroundOpacity + 0.08, 0.18)
        let appliedOpacity = isHovering ? hoveredOpacity : backgroundOpacity
        return Color.white.opacity(min(appliedOpacity, 0.32))
    }

    private var contentTransition: ContentTransition {
        switch symbolEffect {
        case .replace, .replaceAndBounce, .wiggle:
            .symbolEffect(.replace)
        }
    }

    private func triggerPressEffect() {
        switch interaction {
        case .none:
            triggerBounceIfNeeded()
        case .nudge(let amount):
            withAnimation(.spring(response: 0.12, dampingFraction: 0.62)) {
                pressOffset = amount
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(85))
                withAnimation(.spring(response: 0.18, dampingFraction: 0.78)) {
                    pressOffset = 0
                }
            }
        case .wiggle(let direction):
            wiggleToken += 1
            let angle: Double = direction == .clockwise ? 10 : -10

            withAnimation(.spring(response: 0.12, dampingFraction: 0.58)) {
                rotationAngle = angle
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    rotationAngle = 0
                }
            }
        }
    }

    private func triggerBounceIfNeeded() {
        guard symbolEffect == .replaceAndBounce else { return }
        wiggleToken += 1
    }

    enum Interaction {
        case none
        case nudge(CGFloat)
        case wiggle(WiggleDirection)
    }

    enum SymbolEffectStyle: Equatable {
        case replace
        case replaceAndBounce
        case wiggle
    }

    enum WiggleDirection {
        case clockwise
        case counterClockwise
    }
}
