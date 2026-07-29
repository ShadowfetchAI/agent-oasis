import CryptoKit
import XCTest

final class AppStoreConnectConnectorTests: XCTestCase {
    func testTokenUsesES256AndFifteenMinuteLifetime() throws {
        let key = P256.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let token = try AppStoreConnectConnector.makeToken(
            issuerID: "issuer-id",
            keyID: "KEY123",
            privateKeyPEM: key.pemRepresentation,
            now: now
        )

        let segments = token.split(separator: ".").map(String.init)
        XCTAssertEqual(segments.count, 3)

        let header = try decodeJSONSegment(segments[0])
        let payload = try decodeJSONSegment(segments[1])
        XCTAssertEqual(header["alg"] as? String, "ES256")
        XCTAssertEqual(header["kid"] as? String, "KEY123")
        XCTAssertEqual(payload["iss"] as? String, "issuer-id")
        XCTAssertEqual(payload["aud"] as? String, "appstoreconnect-v1")
        XCTAssertEqual(payload["exp"] as? Int, 1_800_000_900)

        let signatureData = try XCTUnwrap(base64URLData(segments[2]))
        XCTAssertEqual(signatureData.count, 64)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: signingInput))
    }

    func testIndividualTokenUsesUserSubjectWithoutIssuer() throws {
        let key = P256.Signing.PrivateKey()
        let token = try AppStoreConnectConnector.makeToken(
            issuerID: "",
            keyID: "KEY123",
            privateKeyPEM: key.pemRepresentation
        )
        let payload = try decodeJSONSegment(String(token.split(separator: ".")[1]))

        XCTAssertNil(payload["iss"])
        XCTAssertEqual(payload["sub"] as? String, "user")
    }

    func testAppsPageParsingPreservesCanonicalIdentifiersAndPagination() throws {
        let data = Data(
            """
            {
              "data": [
                {
                  "type": "apps",
                  "id": "1234567890",
                  "attributes": {
                    "name": "Agent Oasis",
                    "bundleId": "com.realbobcorbin.AgentOasis",
                    "sku": "AGENT-OASIS-MAC",
                    "primaryLocale": "en-US"
                  }
                }
              ],
              "links": {
                "next": "https://api.appstoreconnect.apple.com/v1/apps?cursor=next"
              }
            }
            """.utf8
        )

        let page = try AppStoreConnectConnector.parseAppsPage(data)

        XCTAssertEqual(page.records.count, 1)
        XCTAssertEqual(page.records[0].name, "Agent Oasis")
        XCTAssertEqual(page.records[0].bundleID, "com.realbobcorbin.AgentOasis")
        XCTAssertEqual(page.records[0].sku, "AGENT-OASIS-MAC")
        XCTAssertEqual(
            page.nextURL,
            "https://api.appstoreconnect.apple.com/v1/apps?cursor=next"
        )
    }

    private func decodeJSONSegment(_ value: String) throws -> [String: Any] {
        let data = try XCTUnwrap(base64URLData(value))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func base64URLData(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        return Data(base64Encoded: base64)
    }
}
