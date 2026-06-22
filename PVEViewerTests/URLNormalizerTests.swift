import XCTest
@testable import PVEViewer

final class URLNormalizerTests: XCTestCase {
    func testBareHostDefaultsToHTTPSAndPort8006() throws {
        XCTAssertEqual(try URLNormalizer.normalize("pve").absoluteString, "https://pve:8006")
    }

    func testHostWithPortDefaultsToHTTPSOnly() throws {
        XCTAssertEqual(try URLNormalizer.normalize("pve.local:8006").absoluteString, "https://pve.local:8006")
    }

    func testIPAddressDefaultsToHTTPSAndPort8006() throws {
        XCTAssertEqual(try URLNormalizer.normalize("192.0.2.10").absoluteString, "https://192.0.2.10:8006")
    }

    func testFullURLsRemainUnchanged() throws {
        XCTAssertEqual(try URLNormalizer.normalize("https://pve.example.com/custom").absoluteString, "https://pve.example.com/custom")
        XCTAssertEqual(try URLNormalizer.normalize("http://pve.example.com:8080").absoluteString, "http://pve.example.com:8080")
    }

    func testInvalidInputIsRejected() {
        XCTAssertThrowsError(try URLNormalizer.normalize(""))
        XCTAssertThrowsError(try URLNormalizer.normalize("not a host"))
        XCTAssertThrowsError(try URLNormalizer.normalize("ftp://pve.example.com"))
        XCTAssertThrowsError(try URLNormalizer.normalize("https://"))
    }
}
