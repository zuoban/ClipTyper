import XCTest
@testable import ClipTyper

final class UpdateCheckerTests: XCTestCase {
    // MARK: - Version Comparison

    @MainActor
    func testCompareVersionsSame() async {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.3.1", latest: "v1.3.1"), .orderedSame)
    }

    @MainActor
    func testCompareVersionsSameNoVPrefix() async {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.3.1", latest: "1.3.1"), .orderedSame)
    }

    @MainActor
    func testCompareVersionsNewerPatch() async {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.3.1", latest: "v1.3.2"), .orderedAscending)
    }

    @MainActor
    func testCompareVersionsNewerMinor() async {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.3.1", latest: "v1.4"), .orderedAscending)
    }

    @MainActor
    func testCompareVersionsNewerMajor() async {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.3.1", latest: "v2.0"), .orderedAscending)
    }

    @MainActor
    func testCompareVersionsOlder() async {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.5", latest: "v1.3.1"), .orderedDescending)
    }

    @MainActor
    func testCompareVersionsShortVsLong() async {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.3.1", latest: "v1.3.1.0"), .orderedSame)
    }

    @MainActor
    func testCompareVersionsZeroComparison() async {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "0.0", latest: "v0.0.0"), .orderedSame)
    }

    @MainActor
    func testCompareVersionsNonNumericComponentsGracefullyDegraded() async {
        let updater = makeUpdateChecker()
        // 1.3.1 vs 1.0 (from 1.4-beta) -> 1.3.1 > 1.0 -> descending
        let result = updater.compareVersions(current: "1.3.1", latest: "v1.4-beta")
        XCTAssertEqual(result, .orderedDescending)
    }

    // MARK: - GitHubRelease Decoding

    @MainActor
    func testParseGitHubReleaseValid() throws {
        let json = """
        {
            "tag_name": "v1.3.1",
            "html_url": "https://github.com/zuoban/ClipTyper/releases/tag/v1.3.1",
            "name": "Release v1.3.1"
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v1.3.1")
        XCTAssertEqual(release.htmlURL.absoluteString, "https://github.com/zuoban/ClipTyper/releases/tag/v1.3.1")
        XCTAssertEqual(release.name, "Release v1.3.1")
    }

    @MainActor
    func testParseGitHubReleaseMissingOptionalName() throws {
        let json = """
        {
            "tag_name": "v2.0",
            "html_url": "https://github.com/zuoban/ClipTyper/releases/tag/v2.0"
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v2.0")
        XCTAssertNil(release.name)
    }

    // MARK: - Last Check Date

    @MainActor
    func testLastCheckDateNilWhenNeverChecked() async {
        let defaults = UserDefaults()
        let session = URLSession(configuration: .ephemeral)
        let updater = UpdateChecker(
            session: session,
            defaults: defaults,
            currentVersionProvider: { "1.0" },
            alertHandler: { _ in }
        )
        // Ensure key is missing
        defaults.removeObject(forKey: "lastUpdateCheckTimestamp")
        XCTAssertNil(updater.lastCheckDate)
    }

    @MainActor
    func testCheckForUpdatesUpdatesTimestamp() async {
        let defaults = UserDefaults()
        let session = makeSession(statusCode: 404, data: Data())
        let updater = UpdateChecker(
            session: session,
            defaults: defaults,
            currentVersionProvider: { "1.0" },
            alertHandler: { _ in }
        )
        
        defaults.removeObject(forKey: "lastUpdateCheckTimestamp")

        await updater.checkForUpdates()

        XCTAssertNotNil(updater.lastCheckDate)
        let intervalSinceNow = updater.lastCheckDate!.timeIntervalSinceNow
        XCTAssertGreaterThan(intervalSinceNow, -5)
        
        defaults.removeObject(forKey: "lastUpdateCheckTimestamp")
    }

    // MARK: - Network Layer

    @MainActor
    func testFetchReleaseSuccess() async {
        let json = """
        {
            "tag_name": "v1.3.1",
            "html_url": "https://github.com/zuoban/ClipTyper/releases/tag/v1.3.1",
            "name": null
        }
        """
        let session = makeSession(statusCode: 200, data: json.data(using: .utf8)!)
        let updater = makeUpdateChecker(session: session)

        let release = try? await updater.invokeFetchLatestRelease()

        XCTAssertNotNil(release)
        XCTAssertEqual(release?.tagName, "v1.3.1")
    }

    @MainActor
    func testFetchReleaseReturnsNilOn404() async {
        let session = makeSession(statusCode: 404, data: Data())
        let updater = makeUpdateChecker(session: session)

        let release = try? await updater.invokeFetchLatestRelease()

        XCTAssertNil(release)
    }

    @MainActor
    func testFetchReleaseThrowsOn500() async {
        let session = makeSession(statusCode: 500, data: Data())
        let updater = makeUpdateChecker(session: session)

        do {
            _ = try await updater.invokeFetchLatestRelease()
            XCTFail("Expected error to be thrown")
        } catch let error as UpdateCheckError {
            guard case .serverError(let code) = error else {
                XCTFail("Expected serverError, got \(error)")
                return
            }
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Expected UpdateCheckError, got \(error)")
        }
    }

    @MainActor
    func testFetchReleaseThrowsOnInvalidJSON() async {
        let session = makeSession(statusCode: 200, data: "not json".data(using: .utf8)!)
        let updater = makeUpdateChecker(session: session)

        do {
            _ = try await updater.invokeFetchLatestRelease()
            XCTFail("Expected error to be thrown")
        } catch let error as UpdateCheckError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Expected UpdateCheckError, got \(error)")
        }
    }

    @MainActor
    func testFetchReleaseThrowsOnRateLimit() async {
        let session = makeSession(statusCode: 403, data: Data())
        let updater = makeUpdateChecker(session: session)

        do {
            _ = try await updater.invokeFetchLatestRelease()
            XCTFail("Expected error to be thrown")
        } catch let error as UpdateCheckError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Expected UpdateCheckError, got \(error)")
        }
    }

    @MainActor
    func testFetchReleaseThrowsNoInternet() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ErrorURLProtocol.self]
        let session = URLSession(configuration: config)
        let updater = makeUpdateChecker(session: session)

        do {
            _ = try await updater.invokeFetchLatestRelease()
            XCTFail("Expected error to be thrown")
        } catch let error as UpdateCheckError {
            XCTAssertEqual(error, .noInternet)
        } catch {
            XCTFail("Expected UpdateCheckError, got \(error)")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeUpdateChecker(
        session: URLSession? = nil,
        defaults: UserDefaults? = nil,
        currentVersion: String = "1.0"
    ) -> UpdateChecker {
        let session = session ?? URLSession(configuration: .ephemeral)
        let defaults = defaults ?? UserDefaults()
        return UpdateChecker(
            session: session,
            defaults: defaults,
            currentVersionProvider: { currentVersion },
            alertHandler: { _ in }
        )
    }

    private func makeSession(statusCode: Int, data: Data) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        StubURLProtocol.responseHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.github.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.responseHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class ErrorURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

extension UpdateChecker {
    func invokeFetchLatestRelease() async throws -> GitHubRelease? {
        try await fetchLatestRelease()
    }
}
