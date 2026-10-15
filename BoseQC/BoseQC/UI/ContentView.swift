import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ble: BoseBluetoothClient

    var body: some View {
        Group {
            if ble.phase == .ready {
                connected
            } else {
                browse
            }
        }
        .padding(28)
        .frame(minWidth: 380, idealWidth: 400, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("BoseQC")
                .font(.system(size: 26, weight: .semibold, design: .rounded))

            Text(ble.statusMessage)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(ble.phase == .scanning ? "Stop" : "Scan") {
                    if ble.phase == .scanning { ble.stopScan() } else { ble.startScan() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                if ble.phase == .connecting || ble.phase == .discovering {
                    ProgressView().controlSize(.small)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !ble.discovered.isEmpty {
                VStack(spacing: 8) {
                    ForEach(ble.discovered) { item in
                        Button {
                            ble.connect(to: item)
                        } label: {
                            HStack {
                                Text(item.name)
                                    .font(.body.weight(.medium))
                                Spacer()
                                Text("Connect")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ble.state.name)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(statusLine)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Disconnect") { ble.disconnect() }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Mode")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    modeButton("Quiet", 0)
                    modeButton("Aware", 1)
                    modeButton("Commute", 2)
                }
            }

            if let err = ble.state.lastError {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            Button("Refresh") {
                Task { await ble.refresh() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var statusLine: String {
        var parts: [String] = []
        if let battery = ble.state.batteryPercent {
            parts.append("\(battery)%")
        }
        if let mode = ble.state.modeLabel {
            parts.append(mode)
        } else if let index = ble.state.modeIndex {
            parts.append("Mode \(index)")
        }
        if parts.isEmpty { return ble.statusMessage }
        return parts.joined(separator: " · ")
    }

    private func modeButton(_ title: String, _ index: UInt8) -> some View {
        let selected = ble.state.modeIndex == index
        return Button {
            Task { await ble.setMode(index: index) }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.primary : Color(nsColor: .controlBackgroundColor))
                )
                .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
