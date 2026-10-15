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
        .frame(minWidth: 380, idealWidth: 400, minHeight: 440)
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("BoseQC")
                .font(.system(size: 26, weight: .semibold, design: .rounded))

            Text(ble.statusMessage)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Find headphones") {
                    ble.startScan()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if ble.phase == .connecting {
                    ProgressView().controlSize(.small)
                }
            }

            if ble.discovered.isEmpty {
                Text("Pair your QuietComfort in System Settings → Bluetooth, then Find.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(ble.discovered) { item in
                        Button {
                            ble.connect(to: item)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.body.weight(.medium))
                                    if item.isConnected {
                                        Text("Already connected")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
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
                        .disabled(ble.phase == .connecting)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            if ble.discovered.isEmpty {
                ble.startScan()
            }
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 22) {
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

                if ble.state.modes.isEmpty {
                    Text("Loading modes from headphones…")
                        .foregroundStyle(.secondary)
                    ProgressView().controlSize(.small)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 8
                    ) {
                        ForEach(ble.state.modes) { mode in
                            modeButton(mode)
                        }
                    }
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
        }
        if parts.isEmpty { return ble.statusMessage }
        return parts.joined(separator: " · ")
    }

    private func modeButton(_ mode: DeviceMode) -> some View {
        let selected = ble.state.modeIndex == mode.index
        return Button {
            Task { await ble.setMode(index: mode.index) }
        } label: {
            Text(mode.name)
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
