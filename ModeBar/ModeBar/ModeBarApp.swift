import SwiftUI

@main
struct ModeBarApp: App {
    @StateObject private var session = HeadphoneSession()

    var body: some Scene {
        // MenuBarExtra labels must stay Label + Image (template). Custom Shape
        // views often render blank in the system menu bar.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(session)
        } label: {
            Label {
                Text(menuBarTitle)
            } icon: {
                Image("ModeBarMark")
                    .renderingMode(.template)
                    .opacity(iconOpacity)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private var iconOpacity: Double {
        (session.phase == .ready || session.phase == .connecting) ? 1 : 0.55
    }

    /// Non-empty title keeps the extra visible even if the image fails to load.
    private var menuBarTitle: String {
        if session.phase == .ready, let battery = session.state.batteryPercent {
            return "\(battery)%"
        }
        return "ModeBar"
    }
}
