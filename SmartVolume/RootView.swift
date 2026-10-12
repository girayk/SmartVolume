import SwiftUI

struct RootView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Group {
            if coordinator.setupComplete {
                SettingsView(coordinator: coordinator)
            } else {
                SetupView(coordinator: coordinator)
            }
        }
        .frame(width: 520, height: 520, alignment: .topLeading)
    }
}
