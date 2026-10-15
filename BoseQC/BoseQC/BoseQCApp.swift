import SwiftUI

@main
struct BoseQCApp: App {
    @StateObject private var ble = BoseBluetoothClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .task {
                    // Headphones already linked in System Settings → open RFCOMM immediately.
                    ble.connectPreferred()
                }
        }
        .defaultSize(width: 420, height: 480)
    }
}
