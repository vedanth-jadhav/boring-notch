//
//  LockScreenLyricLineView.swift
//  boringNotch
//
//  Extracted from LockScreenMusicWidgetView for reuse in floating lyrics.
//

import SwiftUI

struct LockScreenLyricLineView: View {
    let line: LockScreenLyricDisplayLine

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(line.displayText)
                .font(font)
                .foregroundStyle(foreground)
                .lineSpacing(2)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadow(color: .black.opacity(0.28), radius: 1, y: 1)
        }
        .opacity(opacity)
        .scaleEffect(scale, anchor: .leading)
        .accessibilityLabel(line.displayText)
    }

    private var font: Font {
        switch line.role {
        case .current:
            .system(size: 20, weight: .bold, design: .rounded)
        case .previous:
            .system(size: 14, weight: .semibold, design: .rounded)
        case .upcoming(let offset):
            .system(size: offset == 1 ? 16 : 14, weight: .semibold, design: .rounded)
        }
    }

    private var foreground: Color {
        switch line.role {
        case .current:
            .white
        case .previous:
            .white.opacity(0.42)
        case .upcoming(let offset):
            .white.opacity(offset == 1 ? 0.72 : 0.5)
        }
    }

    private var opacity: Double {
        switch line.role {
        case .current:
            1
        case .previous:
            0.62
        case .upcoming(let offset):
            offset == 1 ? 0.88 : 0.66
        }
    }

    private var scale: CGFloat {
        switch line.role {
        case .current:
            1
        case .previous:
            0.96
        case .upcoming:
            0.98
        }
    }

    private var lineLimit: Int {
        switch line.role {
        case .current:
            3
        case .previous, .upcoming:
            1
        }
    }
}
