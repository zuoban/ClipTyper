import Combine
import SwiftUI
import KeyboardShortcuts

struct AppMenuView: View {
    @ObservedObject private var autoTyper = AutoTyper.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var isTrusted: Bool = AccessibilityHelper.isTrusted
    private let permissionPollTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text(NSLocalizedString("ClipTyper", comment: ""))
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Configuration Sliders
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(NSLocalizedString("Total Duration", comment: ""))
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(settings.totalDurationMs)) \(NSLocalizedString("ms", comment: ""))")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.totalDurationMs, in: AppConstants.totalDurationRange, step: AppConstants.totalDurationStep)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(NSLocalizedString("Jitter", comment: ""))
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(settings.typingJitterMs)) \(NSLocalizedString("ms", comment: ""))")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.typingJitterMs, in: AppConstants.jitterRange, step: AppConstants.jitterStep)
                }
            }

            Divider()

            // Status
            HStack {
                Text(NSLocalizedString("Status", comment: ""))
                    .font(.subheadline)
                Spacer()
                Text(autoTyper.isTyping ? NSLocalizedString("Typing", comment: "") : NSLocalizedString("Ready", comment: ""))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(autoTyper.isTyping ? .accentColor : .secondary)
            }

            if autoTyper.typingProgress.total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(NSLocalizedString("Progress", comment: ""))
                            .font(.subheadline)
                        Spacer()
                        Text("\(autoTyper.typingProgress.current) / \(autoTyper.typingProgress.total)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: autoTyper.typingProgress.fractionCompleted)
                        .controlSize(.small)
                }
            }

            if let feedbackMessage = autoTyper.feedbackMessage {
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Shortcut Recorder
            HStack {
                Text(NSLocalizedString("Shortcut", comment: ""))
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
                        AccessibilityHelper.openSystemSettings()
                    }
                    isTrusted = AccessibilityHelper.isTrusted
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isTrusted ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(isTrusted ? NSLocalizedString("Permission OK", comment: "") : NSLocalizedString("Authorize", comment: ""))
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(NSLocalizedString("Quit", comment: "")) {
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isTrusted = AccessibilityHelper.isTrusted
        }
        .onReceive(permissionPollTimer) { _ in
            isTrusted = AccessibilityHelper.isTrusted
        }
    }
}
