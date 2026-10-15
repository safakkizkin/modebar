import SwiftUI

@main
struct BoseQCApp: App {
    @StateObject private var ble = BoseBluetoothClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
        }
        .defaultSize(width: 460, height: 600)
    }
}
