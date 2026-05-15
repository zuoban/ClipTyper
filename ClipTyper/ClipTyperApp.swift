import SwiftUI

@main
struct ClipTyperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var autoTyper = AutoTyper.shared

    var body: some Scene {
        MenuBarExtra {
            AppMenuView()
        } label: {
            Image(systemName: autoTyper.isTyping ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}
