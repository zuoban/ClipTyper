import XCTest
@testable import ClipTyper

@MainActor
final class UpdateCheckerTests: XCTestCase {
    // MARK: - Version Comparison

    func testCompareVersionsSame() {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.2", latest: "v1.2"), .orderedSame)
    }

    func testCompareVersionsSameNoVPrefix() {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.2", latest: "1.2"), .orderedSame)
    }

    func testCompareVersionsNewerPatch() {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.2", latest: "v1.2.1"), .orderedAscending)
    }

    func testCompareVersionsNewerMinor() {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.2", latest: "v1.3"), .orderedAscending)
    }

    func testCompareVersionsNewerMajor() {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.2", latest: "v2.0"), .orderedAscending)
    }

    func testCompareVersionsOlder() {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.5", latest: "v1.3"), .orderedDescending)
    }

    func testCompareVersionsShortVsLong() {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "1.2", latest: "v1.2.0.0"), .orderedSame)
    }

    func testCompareVersionsZeroComparison() {
        let updater = makeUpdateChecker()
        XCTAssertEqual(updater.compareVersions(current: "0.0", latest: "v0.0.0"), .orderedSame)
    }

    func testCompareVersionsNonNumericComponentsGracefullyDegraded() {
        let updater = makeUpdateChecker()
        let result = updater.compareVersions(current: "1.2", latest: "v1.3-beta")
        XCTAssertEqual(result, .orderedDescending)
    }

    // MARK: - GitHubRelease Decoding

    func testParseGitHubReleaseValid() throws {
        let json = """
        {
            "tag_name": "v1.3.0",
            "html_url": "https://github.com/zuoban/ClipTyper/releases/tag/v1.3.0",
            "name": "Release v1.3.0"
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v1.3.0")
        XCTAssertEqual(release.htmlURL.absoluteString, "https://github.com/zuoban/ClipTyper/releases/tag/v1.3.0")
        XCTAssertEqual(release.name, "Release v1.3.0")
    }

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

    func testLastCheckDateNilWhenNeverChecked() {
        let updater = UpdateChecker(
            session: .shared,
            currentVersionProvider: { "1.0" }
        )
        XCTAssertNil(updater.lastCheckDate)
    }

    func testCheckForUpdatesUpdatesTimestamp() async {
        let session = makeSession(statusCode: 404, data: Data())
        let updater = UpdateChecker(
            session: session,
            currentVersionProvider: { "1.0" }
        )

        await updater.checkForUpdates()

        XCTAssertNotNil(updater.lastCheckDate)
        let intervalSinceNow = updater.lastCheckDate!.timeIntervalSinceNow
        XCTAssertGreaterThan(intervalSinceNow, -5)
    }

    // MARK: - Network Layer

    func testFetchReleaseSuccess() async {
        let json = """
        {
            "tag_name": "v1.3.0",
            "html_url": "https://github.com/zuoban/ClipTyper/releases/tag/v1.3.0",
            "name": null
        }
        """
        let session = makeSession(statusCode: 200, data: json.data(using: .utf8)!)
        let updater = makeUpdateChecker(session: session)

        let release = try? await updater.invokeFetchLatestRelease()

        XCTAssertNotNil(release)
        XCTAssertEqual(release?.tagName, "v1.3.0")
    }

    func testFetchReleaseReturnsNilOn404() async {
        let session = makeSession(statusCode: 404, data: Data())
        let updater = makeUpdateChecker(session: session)

        let release = try? await updater.invokeFetchLatestRelease()

        XCTAssertNil(release)
    }

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

    private func makeUpdateChecker(
        session: URLSession = .shared,
        currentVersion: String = "1.0"
    ) -> UpdateChecker {
        UpdateChecker(
            session: session,
            currentVersionProvider: { currentVersion }
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
