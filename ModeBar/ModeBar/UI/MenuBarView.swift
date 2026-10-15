import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var session: HeadphoneSession

    var body: some View {
        Group {
            Text(headerTitle)

            if session.phase == .ready {
                if let battery = session.state.batteryPercent {
                    Text("Battery \(battery)%")
                }

                Divider()

                if session.state.modes.isEmpty {
                    Text("Loading modes…")
                } else {
                    ForEach(session.state.modes) { mode in
                        let selected = session.state.modeIndex == mode.index
                        Button {
                            Task { await session.setMode(index: mode.index) }
                        } label: {
                            // Native checkmark via attributed title keeps spacing clean.
                            Text((selected ? "✓ " : "    ") + mode.name)
                        }
                    }
                }
            } else if session.phase == .connecting {
                Text(session.statusMessage)
            } else {
                Text(session.statusMessage)

                if !session.discovered.isEmpty {
                    Divider()
                    ForEach(session.discovered) { item in
                        Button(item.name) {
                            session.connect(to: item)
                        }
                    }
                }

                Button("Connect headphones") {
                    session.connectPreferred()
                }
            }

            if let err = session.state.lastError, session.phase != .ready {
                Text(err)
            }

            Divider()

            Button("Quit ModeBar") {
                session.disconnect()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .task {
            session.connectPreferred()
        }
    }

    private var headerTitle: String {
        session.phase == .ready ? session.state.name : "ModeBar"
    }
}
