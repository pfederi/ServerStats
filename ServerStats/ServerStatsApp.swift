import SwiftUI

@main
struct ServerStatsApp: App {
    @StateObject private var monitor: ServerMonitor

    init() {
        let m = ServerMonitor()
        _monitor = StateObject(wrappedValue: m)
        // Start polling immediately on app launch, not on first dropdown open
        Task { @MainActor in
            NSApp.appearance = NSAppearance(named: .darkAqua)
            m.startPolling()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            DropdownView(monitor: monitor)
        } label: {
            let img = StatusBarRenderer.render(monitor: monitor)
            Image(nsImage: img)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(monitor)
        }
    }
}
