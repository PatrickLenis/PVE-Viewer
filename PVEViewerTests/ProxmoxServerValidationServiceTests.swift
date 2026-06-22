import XCTest
@testable import PVEViewer

final class ProxmoxServerValidationServiceTests: XCTestCase {
    func testValidationURLUsesOriginAndVersionEndpoint() throws {
        let input = try XCTUnwrap(URL(string: "https://pve.example.com:8006/custom/path?x=1"))

        let validationURL = try ProxmoxServerValidationService.validationURL(for: input)

        XCTAssertEqual(validationURL.absoluteString, "https://pve.example.com:8006/api2/json/version")
    }

    func testValidVersionPayloadIsAccepted() {
        let json = Data(#"{"data":{"version":"8.2.4","release":"8.2","repoid":"fixture"}}"#.utf8)

        XCTAssertTrue(ProxmoxServerValidationService.isValidVersionPayload(json))
    }

    func testProxmoxServerHeaderIsAccepted() throws {
        let url = try XCTUnwrap(URL(string: "https://pve.example.com:8006/api2/json/version"))
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Server": "pve-api-daemon/3.0"]
            )
        )

        XCTAssertTrue(ProxmoxServerValidationService.hasProxmoxServerHeader(response))
    }

    func testMissingVersionPayloadIsRejected() {
        let json = Data(#"{"data":{"name":"not-proxmox"}}"#.utf8)

        XCTAssertFalse(ProxmoxServerValidationService.isValidVersionPayload(json))
    }

    func testNonJSONPayloadIsRejected() {
        XCTAssertFalse(ProxmoxServerValidationService.isValidVersionPayload(Data("<html>YouTube</html>".utf8)))
    }
}
