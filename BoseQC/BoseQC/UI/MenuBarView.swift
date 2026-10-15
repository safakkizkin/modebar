import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var session: BoseBluetoothClient

    var body: some View {
        Group {
            Text(headerTitle)

            if session.phase == .ready {
                if let battery = session.state.batteryPercent {
                    Text("Battery \(battery)%")
                }
                if let mode = session.state.modeLabel {
                    Text(mode)
                }

                Divider()

                if session.state.modes.isEmpty {
                    Text("Loading modes…")
                } else {
                    ForEach(session.state.modes) { mode in
                        let selected = session.state.modeIndex == mode.index
                        Button((selected ? "✓ " : "    ") + mode.name) {
                            Task { await session.setMode(index: mode.index) }
                        }
                    }
                }

                Divider()

                Button("Refresh") {
                    Task { await session.refresh(full: true) }
                }
                Button("Disconnect") {
                    session.disconnect()
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

            Button("Quit BoseQC") {
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
        session.phase == .ready ? session.state.name : "BoseQC"
    }
}
