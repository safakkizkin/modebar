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
                Image(nsImage: ModeBarMarkImage.template(pointSize: 16))
                    .renderingMode(.template)
                    .opacity(iconOpacity)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private var iconOpacity: Double {
        (session.phase == .ready || session.phase == .connecting) ? 1 : 0.55
    }

    /// Empty when connected so only the mark (+ optional battery) shows — no "ModeBar" clutter.
    private var menuBarTitle: String {
        if session.phase == .ready, let battery = session.state.batteryPercent {
            return "\(battery)%"
        }
        return ""
    }
}
