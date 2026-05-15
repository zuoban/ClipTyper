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
        let timestamp = defaults.double(forKey: lastCheckKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    private let session: URLSession
    private let defaults: UserDefaults
    private let currentVersionProvider: @MainActor () -> String?
    private let releaseURL: URL
    private let alertHandler: @MainActor (UpdateAlert) -> Void

    enum UpdateAlert {
        case upToDate(currentVersion: String)
        case updateAvailable(currentVersion: String, release: GitHubRelease)
        case error(message: String)
    }

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        currentVersionProvider: (@MainActor () -> String?)? = nil,
        releaseURL: URL = URL(string: "https://api.github.com/repos/zuoban/ClipTyper/releases/latest")!,
        alertHandler: (@MainActor (UpdateAlert) -> Void)? = nil
    ) {
        self.session = session
        self.defaults = defaults
        self.currentVersionProvider = currentVersionProvider ?? {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        }
        self.releaseURL = releaseURL
        self.alertHandler = alertHandler ?? { _ in }
    }

    func checkForUpdates() async {
        alertHandler(await checkForUpdatesResult())
    }

    func checkForUpdatesResult() async -> UpdateAlert {
        defaults.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

        guard let currentVersion = currentVersionProvider() else {
            return .error(message: NSLocalizedString("Unable to determine current app version.", comment: ""))
        }

        do {
            guard let release = try await fetchLatestRelease() else {
                return .upToDate(currentVersion: currentVersion)
            }

            switch compareVersions(current: currentVersion, latest: release.tagName) {
            case .orderedAscending:
                return .updateAvailable(currentVersion: currentVersion, release: release)
            default:
                return .upToDate(currentVersion: currentVersion)
            }
        } catch let error as UpdateCheckError {
            return .error(message: error.localizedDescription)
        } catch {
            return .error(message: error.localizedDescription)
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

}
