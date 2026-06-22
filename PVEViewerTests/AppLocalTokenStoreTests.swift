import Foundation
import XCTest
@testable import PVEViewer

final class AppLocalTokenStoreTests: XCTestCase {
    func testSaveLoadAndDeleteTokenFromLocalFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("APITokens.json")
        let store = AppLocalTokenStore(fileURL: fileURL)
        let id = UUID()
        let token = ProxmoxAPIToken(tokenID: "fixture@pve!viewer", secret: "fixture-token-value")

        try store.saveToken(token, for: id)
        XCTAssertEqual(try store.loadToken(for: id), token)

        let savedData = try Data(contentsOf: fileURL)
        XCTAssertTrue(String(decoding: savedData, as: UTF8.self).contains("fixture-token-value"))

        let updated = ProxmoxAPIToken(tokenID: "fixture@pve!viewer", secret: "updated-token-value")
        try store.saveToken(updated, for: id)
        XCTAssertEqual(try store.loadToken(for: id), updated)

        try store.deleteToken(for: id)
        XCTAssertNil(try store.loadToken(for: id))
    }
}
