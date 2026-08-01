//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void

    private let selectionAnimation = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.9, blendDuration: 0.04)
    
    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .font(.system(size: selected ? 13 : 12, weight: selected ? .semibold : .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, height: 24)
                .contentShape(Capsule())
                .scaleEffect(selected ? 1.0 : 0.94)
                .offset(y: selected ? -0.5 : 0)
                .animation(selectionAnimation, value: selected)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

#if !SWIFT_PACKAGE
#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
#endif
