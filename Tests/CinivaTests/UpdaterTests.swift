@testable import Ciniva
import CryptoKit
import XCTest

final class UpdaterTests: XCTestCase {
    func testVersionOrdering() {
        XCTAssertTrue(Updater.isNewer("1.2.0", than: "1.1.9"))
        XCTAssertTrue(Updater.isNewer("1.10", than: "1.9.5"))
        XCTAssertTrue(Updater.isNewer("1.0.1", than: "1.0"))
        XCTAssertFalse(Updater.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(Updater.isNewer("0.9", than: "1.0"))
    }

    func testSignatureVerification() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        let data = Data("update archive".utf8)
        let sig = Data(try key.signature(for: data).base64EncodedString().utf8)
        XCTAssertNoThrow(try Updater.verify(data, signature: sig, publicKey: pub))
        XCTAssertThrowsError(try Updater.verify(Data("tampered".utf8), signature: sig, publicKey: pub))
        XCTAssertThrowsError(try Updater.verify(data, signature: sig, publicKey: Updater.publicKey))
    }
}
