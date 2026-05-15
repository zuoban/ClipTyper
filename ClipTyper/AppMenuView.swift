import Combine
import SwiftUI
import KeyboardShortcuts

struct AppMenuView: View {
    @ObservedObject private var autoTyper = AutoTyper.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var isTrusted: Bool = AccessibilityHelper.isTrusted
    @State private var isShowingAbout = false
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

            // About & Updates
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isShowingAbout.toggle()
                    }
                } label: {
                    HStack {
                        Text(NSLocalizedString("About ClipTyper", comment: ""))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: isShowingAbout ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if isShowingAbout {
                    AboutMenuSection()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
        .frame(width: 300)
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

private struct AboutMenuSection: View {
    @State private var updateState: UpdateState = .idle

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                AppIconView()

                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("ClipTyper", comment: ""))
                        .font(.subheadline.weight(.semibold))
                    Text(String.localizedStringWithFormat(NSLocalizedString("Version %@", comment: ""), appVersion))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                Link(destination: URL(string: "https://github.com/zuoban/ClipTyper")!) {
                    Label("GitHub", systemImage: "arrow.up.right")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.55))
                .frame(height: 1)

            UpdateStatusRow(updateState: updateState) {
                Task {
                    await checkForUpdates()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private func checkForUpdates() async {
        updateState = .checking
        let result = await UpdateChecker.shared.checkForUpdatesResult()
        switch result {
        case .upToDate(let currentVersion):
            updateState = .upToDate(currentVersion: currentVersion)
        case .updateAvailable(let currentVersion, let release):
            updateState = .updateAvailable(currentVersion: currentVersion, release: release)
        case .error(let message):
            updateState = .error(message: message)
        }
    }
}

private struct UpdateStatusRow: View {
    let updateState: UpdateState
    let checkForUpdates: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: updateState.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(updateState.symbolColor)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(updateState.symbolColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Updates", comment: ""))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)

                if let message = updateState.message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(updateState.isError ? .red : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if updateState.isChecking {
                ProgressView()
                    .controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    if case .updateAvailable(_, let release) = updateState {
                        Button(NSLocalizedString("Download", comment: "")) {
                            NSWorkspace.shared.open(release.htmlURL)
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    }

                    Button(updateState.primaryButtonTitle) {
                        checkForUpdates()
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 1)
    }
}

private struct AppIconView: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            )
    }
}

private enum UpdateState {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case updateAvailable(currentVersion: String, release: GitHubRelease)
    case error(message: String)

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .checking:
            return NSLocalizedString("Checking for updates...", comment: "")
        case .upToDate(let currentVersion):
            return String.localizedStringWithFormat(
                NSLocalizedString("ClipTyper %@ is currently the newest version available.", comment: ""),
                currentVersion
            )
        case .updateAvailable(let currentVersion, let release):
            return String.localizedStringWithFormat(
                NSLocalizedString("A new version of ClipTyper is available: %@ (you have %@).", comment: ""),
                release.tagName,
                currentVersion
            )
        case .error(let message):
            return NSLocalizedString("An error occurred while checking for updates.", comment: "")
                + "\n" + message
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .checking:
            return NSLocalizedString("Checking...", comment: "")
        default:
            return NSLocalizedString("Check for Updates...", comment: "")
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "arrow.triangle.2.circlepath"
        case .checking:
            return "clock"
        case .upToDate:
            return "checkmark"
        case .updateAvailable:
            return "arrow.down"
        case .error:
            return "exclamationmark"
        }
    }

    var symbolColor: Color {
        switch self {
        case .idle, .checking:
            return .secondary
        case .upToDate:
            return .green
        case .updateAvailable:
            return .accentColor
        case .error:
            return .red
        }
    }

    var isChecking: Bool {
        if case .checking = self {
            return true
        }
        return false
    }

    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
}
