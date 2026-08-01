//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    var id: NotchViews { view }
    let label: String
    let icon: String
    let view: NotchViews
}

private let baseTabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "System", icon: "waveform.path.ecg", view: .system)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var budsModel = BudsAppModel.shared
    @Default(.boringShelf) private var boringShelf
    @Namespace var animation

    private let tabAnimation = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.04)

    private var availableTabs: [TabModel] {
        var tabs = baseTabs
        if budsModel.shouldShowTab {
            tabs.append(TabModel(label: "Buds", icon: "earbuds", view: .buds))
        }
        if boringShelf {
            tabs.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        return tabs
    }

    var body: some View {
        let selectedView = coordinator.currentView

        HStack(spacing: 3) {
            ForEach(availableTabs) { tab in
                let isSelected = selectedView == tab.view

                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    select(tab.view)
                }
                .frame(width: 32, height: 24)
                .foregroundStyle(isSelected ? .white : .gray)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .shadow(color: .white.opacity(0.08), radius: 4, y: 1)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    }
                }
            }
        }
        .padding(2)
        .onAppear {
            budsModel.refreshClassicConnection()
        }
        .onChange(of: budsModel.shouldShowTab) { _, shouldShowTab in
            guard !shouldShowTab, coordinator.currentView == .buds else { return }
            withAnimation(tabAnimation) {
                coordinator.currentView = .home
            }
        }
        .background {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .clipShape(Capsule())
        .fixedSize()
    }

    private func select(_ view: NotchViews) {
        guard coordinator.currentView != view else { return }

        withAnimation(tabAnimation) {
            coordinator.currentView = view
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
#endif
