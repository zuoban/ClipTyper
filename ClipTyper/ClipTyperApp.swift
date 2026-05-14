//
//  ClipTyperApp.swift
//  ClipTyper
//
//  Created by 王锦强 on 2026/5/15.
//

import SwiftUI
import KeyboardShortcuts

@main
struct ClipTyperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            AppMenuView()
        } label: {
            Image(systemName: AutoTyper.shared.isTyping ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}

struct AppMenuView: View {
    @ObservedObject private var autoTyper = AutoTyper.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var isTrusted: Bool = AccessibilityHelper.isTrusted
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("ClipTyper")
                    .font(.headline)
                Spacer()
            }
            
            Divider()
            
            // Configuration Sliders
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Total Duration")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(settings.totalDurationMs)) ms")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.totalDurationMs, in: 100...3000, step: 100)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Jitter")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(settings.typingJitterMs)) ms")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.typingJitterMs, in: 0...500, step: 10)
                }
            }
            
            Divider()
            
            // Shortcut Recorder
            HStack {
                Text("Shortcut")
                    .font(.subheadline)
                Spacer()
                KeyboardShortcuts.Recorder(for: .toggleTyping)
            }
            
            Divider()
            
            // Footer with Permissions & Quit
            HStack {
                Button {
                    if !isTrusted {
                        AccessibilityHelper.requestPermission()
                    }
                    isTrusted = AccessibilityHelper.isTrusted
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isTrusted ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(isTrusted ? "Permission OK" : "Authorize")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            isTrusted = AccessibilityHelper.isTrusted
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set default shortcut on first launch (Cmd+Shift+V)
        if KeyboardShortcuts.getShortcut(for: .toggleTyping) == nil {
            KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .shift]), for: .toggleTyping)
        }
        
        registerShortcuts()
        
        // Check permissions on launch and prompt if needed
        checkPermissions()
    }
    
    private func checkPermissions() {
        if !AccessibilityHelper.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Accessibility Permission Required", comment: "")
                alert.informativeText = NSLocalizedString("ClipTyper needs accessibility permissions to simulate keystrokes. Please allow it in System Settings.", comment: "")
                alert.addButton(withTitle: NSLocalizedString("Authorize", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    AccessibilityHelper.requestPermission()
                } else if response == .alertSecondButtonReturn {
                    NSApp.terminate(nil)
                }
            }
        }
    }
    
    private func registerShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .toggleTyping) {
            Task { @MainActor in
                AutoTyper.shared.toggleTyping()
            }
        }
    }
}

extension KeyboardShortcuts.Name {
    static let toggleTyping = Self("toggleTyping")
}
