import Cocoa

struct GitHubRelease: Codable, Sendable {
    let tagName: String
    let htmlURL: URL
    let name: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name
    }
}

enum UpdateCheckError: LocalizedError, Sendable, Equatable {
    case noInternet
    case timeout
    case serverError(Int)
    case invalidResponse
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .noInternet:
            return NSLocalizedString("No internet connection", comment: "")
        case .timeout:
            return NSLocalizedString("The update server did not respond in time.", comment: "")
        case .serverError(let code):
            return String.localizedStringWithFormat(
                NSLocalizedString("Server error (HTTP %d)", comment: ""),
                code
            )
        case .invalidResponse:
            return NSLocalizedString("Unexpected response from update server.", comment: "")
        case .rateLimited:
            return NSLocalizedString("Unable to check right now. Please try again later.", comment: "")
        }
    }
}

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let lastCheckKey = "lastUpdateCheckTimestamp"

    var lastCheckDate: Date? {
        let timestamp = UserDefaults.standard.double(forKey: lastCheckKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    private let session: URLSession
    private let currentVersionProvider: @MainActor () -> String?
    private let releaseURL: URL

    init(
        session: URLSession = .shared,
        currentVersionProvider: (@MainActor () -> String?)? = nil,
        releaseURL: URL = URL(string: "https://api.github.com/repos/zuoban/ClipTyper/releases/latest")!
    ) {
        self.session = session
        self.currentVersionProvider = currentVersionProvider ?? {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        }
        self.releaseURL = releaseURL
    }

    func checkForUpdates() async {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

        guard let currentVersion = currentVersionProvider() else {
            showErrorAlert(message: NSLocalizedString("Unable to determine current app version.", comment: ""))
            return
        }

        do {
            guard let release = try await fetchLatestRelease() else {
                showUpToDateAlert(currentVersion: currentVersion)
                return
            }

            switch compareVersions(current: currentVersion, latest: release.tagName) {
            case .orderedAscending:
                showUpdateAvailableAlert(currentVersion: currentVersion, release: release)
            default:
                showUpToDateAlert(currentVersion: currentVersion)
            }
        } catch let error as UpdateCheckError {
            showErrorAlert(message: error.localizedDescription)
        } catch {
            showErrorAlert(message: error.localizedDescription)
        }
    }

    nonisolated func compareVersions(current: String, latest: String) -> ComparisonResult {
        let latestClean: String
        if latest.hasPrefix("v") || latest.hasPrefix("V") {
            latestClean = String(latest.dropFirst())
        } else {
            latestClean = latest
        }

        var currentParts = current.split(separator: ".").compactMap { Int($0) }
        var latestParts = latestClean.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(currentParts.count, latestParts.count)
        currentParts.append(contentsOf: Array(repeating: 0, count: maxLen - currentParts.count))
        latestParts.append(contentsOf: Array(repeating: 0, count: maxLen - latestParts.count))

        for (c, l) in zip(currentParts, latestParts) {
            if c < l { return .orderedAscending }
            if c > l { return .orderedDescending }
        }
        return .orderedSame
    }

    func fetchLatestRelease() async throws -> GitHubRelease? {
        var request = URLRequest(url: releaseURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClipTyper", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw UpdateCheckError.noInternet
            case .timedOut:
                throw UpdateCheckError.timeout
            default:
                throw UpdateCheckError.noInternet
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(GitHubRelease.self, from: data)
            } catch {
                throw UpdateCheckError.invalidResponse
            }
        case 403, 429:
            throw UpdateCheckError.rateLimited
        case 404:
            return nil
        default:
            throw UpdateCheckError.serverError(httpResponse.statusCode)
        }
    }

    private func showUpToDateAlert(currentVersion: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("You're up to date!", comment: "")
        alert.informativeText = String.localizedStringWithFormat(
            NSLocalizedString("ClipTyper %@ is currently the newest version available.", comment: ""),
            currentVersion
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }

    private func showUpdateAvailableAlert(currentVersion: String, release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("New Version Available", comment: "")
        alert.informativeText = String.localizedStringWithFormat(
            NSLocalizedString("A new version of ClipTyper is available: %@ (you have %@).", comment: ""),
            release.tagName,
            currentVersion
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("Download", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Unable to Check for Updates", comment: "")
        alert.informativeText = NSLocalizedString("An error occurred while checking for updates.", comment: "")
            + "\n\n" + message
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }
}
