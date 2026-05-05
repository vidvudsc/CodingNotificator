import SwiftUI
import AppKit

@main
struct CodingNotificatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Coding Notificator", systemImage: "terminal.fill") {
            UsagePanelView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
                .frame(width: 1, height: 1)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotchNotifierModel.shared.start()
    }
}
