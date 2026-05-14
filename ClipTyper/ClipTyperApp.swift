//
//  ClipTyperApp.swift
//  ClipTyper
//
//  Created by 王锦强 on 2026/5/15.
//

import SwiftUI

@main
struct ClipTyperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isTyping = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarIconStateView(isTyping: $isTyping)
            AppMenuView()
        } label: {
            Image(systemName: isTyping ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}

// Helper view to bridge Combine publisher into @State
struct MenuBarIconStateView: View {
    @Binding var isTyping: Bool

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(AutoTyper.shared.$isTyping) { newValue in
                isTyping = newValue
            }
    }
}
