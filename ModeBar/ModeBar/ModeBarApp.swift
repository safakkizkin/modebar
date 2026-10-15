import SwiftUI

@main
struct ModeBarApp: App {
    @StateObject private var session = HeadphoneSession()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(session)
        } label: {
            HStack(spacing: 4) {
                ModeBarMarkLabel(dimmed: session.phase != .ready && session.phase != .connecting)
                if !menuBarTitle.isEmpty {
                    Text(menuBarTitle)
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarTitle: String {
        guard session.phase == .ready, let battery = session.state.batteryPercent else {
            return ""
        }
        return "\(battery)%"
    }
}
