import SwiftUI

@main
struct ModeBarApp: App {
    @StateObject private var session = HeadphoneSession()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(session)
        } label: {
            Label {
                Text(menuBarTitle)
            } icon: {
                Image(systemName: menuBarSymbol)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarSymbol: String {
        if session.phase == .ready {
            return "headphones"
        }
        if session.phase == .connecting {
            return "headphones"
        }
        return "headphones.slash"
    }

    private var menuBarTitle: String {
        guard session.phase == .ready, let battery = session.state.batteryPercent else {
            return ""
        }
        return " \(battery)%"
    }
}
