import CryptoKit
import Foundation

struct AppStoreAppRecord: Hashable {
    var id: String
    var name: String
    var bundleID: String
    var sku: String
    var primaryLocale: String
}

enum AppStoreConnectConnectorError: LocalizedError {
    case missingConfiguration(String)
    case invalidPrivateKey
    case invalidResponse
    case requestFailed(status: Int, message: String)
    case paginationLimit

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let field):
            "App Store Connect requires \(field)."
        case .invalidPrivateKey:
            "The selected vault item is not a valid App Store Connect .p8 private key."
        case .invalidResponse:
            "App Store Connect returned an unrecognized response."
        case .requestFailed(let status, let message):
            "App Store Connect returned HTTP \(status): \(message)"
        case .paginationLimit:
            "App Store Connect returned more result pages than Agent Oasis can safely process at once."
        }
    }
}

enum AppStoreConnectConnector {
    private static let audience = "appstoreconnect-v1"
    private static let maximumPages = 20

    static func fetchApps(
        issuerID: String,
        keyID: String,
        privateKeyPEM: String,
        session: URLSession = .shared
    ) async throws -> [AppStoreAppRecord] {
        let trimmedKeyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyID.isEmpty else {
            throw AppStoreConnectConnectorError.missingConfiguration("a Key ID")
        }
        let token = try makeToken(
            issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            keyID: trimmedKeyID,
            privateKeyPEM: privateKeyPEM
        )

        var components = URLComponents(
            string: "https://api.appstoreconnect.apple.com/v1/apps"
        )
        components?.queryItems = [
            URLQueryItem(name: "fields[apps]", value: "name,bundleId,sku,primaryLocale"),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard var nextURL = components?.url else {
            throw AppStoreConnectConnectorError.invalidResponse
        }

        var pageCount = 0
        var records: [AppStoreAppRecord] = []
        while pageCount < maximumPages {
            pageCount += 1
            var request = URLRequest(url: nextURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 30
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppStoreConnectConnectorError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AppStoreConnectConnectorError.requestFailed(
                    status: http.statusCode,
                    message: sanitizedErrorMessage(from: data)
                )
            }

            let page = try parseAppsPage(data)
            records.append(contentsOf: page.records)
            guard let next = page.nextURL else {
                return deduplicated(records)
            }
            guard let parsedNext = URL(string: next),
                  parsedNext.scheme == "https",
                  parsedNext.host == "api.appstoreconnect.apple.com" else {
                throw AppStoreConnectConnectorError.invalidResponse
            }
            nextURL = parsedNext
        }

        throw AppStoreConnectConnectorError.paginationLimit
    }

    static func makeToken(
        issuerID: String,
        keyID: String,
        privateKeyPEM: String,
        now: Date = Date()
    ) throws -> String {
        guard !keyID.isEmpty else {
            throw AppStoreConnectConnectorError.missingConfiguration("a Key ID")
        }

        let key: P256.Signing.PrivateKey
        do {
            key = try P256.Signing.PrivateKey(
                pemRepresentation: privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            throw AppStoreConnectConnectorError.invalidPrivateKey
        }

        let header: [String: Any] = [
            "alg": "ES256",
            "kid": keyID,
            "typ": "JWT"
        ]
        let issuedAt = Int(now.timeIntervalSince1970)
        var payload: [String: Any] = [
            "iat": issuedAt,
            "exp": issuedAt + 15 * 60,
            "aud": audience
        ]
        if issuerID.isEmpty {
            payload["sub"] = "user"
        } else {
            payload["iss"] = issuerID
        }

        let encodedHeader = try base64URLJSON(header)
        let encodedPayload = try base64URLJSON(payload)
        let signingInput = "\(encodedHeader).\(encodedPayload)"
        let signature: P256.Signing.ECDSASignature
        do {
            signature = try key.signature(for: Data(signingInput.utf8))
        } catch {
            throw AppStoreConnectConnectorError.invalidPrivateKey
        }
        return "\(signingInput).\(base64URL(signature.rawRepresentation))"
    }

    static func parseAppsPage(
        _ data: Data
    ) throws -> (records: [AppStoreAppRecord], nextURL: String?) {
        let document: AppsDocument
        do {
            document = try JSONDecoder().decode(AppsDocument.self, from: data)
        } catch {
            throw AppStoreConnectConnectorError.invalidResponse
        }

        let records = document.data.compactMap { resource -> AppStoreAppRecord? in
            let name = resource.attributes.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleID = resource.attributes.bundleID
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !bundleID.isEmpty else { return nil }
            return AppStoreAppRecord(
                id: resource.id,
                name: name,
                bundleID: bundleID,
                sku: resource.attributes.sku,
                primaryLocale: resource.attributes.primaryLocale
            )
        }
        return (records, document.links?.next)
    }

    private static func base64URLJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return base64URL(data)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func sanitizedErrorMessage(from data: Data) -> String {
        if let document = try? JSONDecoder().decode(ErrorDocument.self, from: data),
           let error = document.errors.first {
            let message = [error.title, error.detail]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !message.isEmpty {
                return String(message.prefix(500))
            }
        }
        return "The request was not accepted. Verify the key, role, and access settings."
    }

    private static func deduplicated(_ records: [AppStoreAppRecord]) -> [AppStoreAppRecord] {
        var seen: Set<String> = []
        return records.filter { seen.insert($0.id).inserted }
    }
}

private struct AppsDocument: Decodable {
    var data: [AppResource]
    var links: DocumentLinks?
}

private struct AppResource: Decodable {
    var id: String
    var attributes: AppAttributes
}

private struct AppAttributes: Decodable {
    var name: String
    var bundleID: String
    var sku: String
    var primaryLocale: String

    private enum CodingKeys: String, CodingKey {
        case name
        case bundleID = "bundleId"
        case sku
        case primaryLocale
    }
}

private struct DocumentLinks: Decodable {
    var next: String?
}

private struct ErrorDocument: Decodable {
    var errors: [ErrorResource]
}

private struct ErrorResource: Decodable {
    var title: String?
    var detail: String?
}
