import XCTest
@testable import PVEViewer

final class StatusProbeServiceTests: XCTestCase {
    func testSuccessAndRedirectMapToOnline() {
        XCTAssertEqual(StatusProbeService.status(forHTTPStatusCode: 200), .online)
        XCTAssertEqual(StatusProbeService.status(forHTTPStatusCode: 302), .online)
    }

    func testHTTPErrorMapsToError() {
        XCTAssertEqual(StatusProbeService.status(forHTTPStatusCode: 401), .error)
        XCTAssertEqual(StatusProbeService.status(forHTTPStatusCode: 500), .error)
    }

    func testTimeoutMapsToOffline() {
        XCTAssertEqual(StatusProbeService.status(for: URLError(.timedOut)), .offline)
    }

    func testTLSFailureMapsToErrorWhenSelfSignedIsBlocked() {
        XCTAssertEqual(StatusProbeService.status(for: URLError(.serverCertificateUntrusted)), .error)
        XCTAssertEqual(StatusProbeService.status(for: URLError(.serverCertificateHasUnknownRoot)), .error)
    }

    func testTLSFailureMapsToWarningWhenSelfSignedIsAllowed() {
        XCTAssertEqual(
            StatusProbeService.status(
                for: URLError(.serverCertificateUntrusted),
                allowSelfSignedHTTPS: true
            ),
            .tlsWarning
        )
    }

    func testSelfSignedAllowedStillUsesHTTPOutcome() {
        XCTAssertEqual(StatusProbeService.status(forHTTPStatusCode: 200), .online)
        XCTAssertEqual(StatusProbeService.status(forHTTPStatusCode: 403), .error)
    }
}
