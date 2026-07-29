import CryptoKit
import Foundation

enum CredentialInventoryService {
    static func scan(folder: URL, limit: Int = 2_000) throws -> [CredentialInventoryItem] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .nameKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else { return [] }

        var results: [CredentialInventoryItem] = []
        for case let url as URL in enumerator {
            if results.count >= limit { break }
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, isCredentialCandidate(url) else { continue }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            let hash = SHA256.hash(data: Data(url.path.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            results.append(
                CredentialInventoryItem(
                    filename: url.lastPathComponent,
                    service: inferredService(from: url),
                    fileSize: Int64(values.fileSize ?? 0),
                    posixPermissions: String(format: "%03o", permissions),
                    modifiedAt: values.contentModificationDate,
                    indexedAt: Date(),
                    sourcePathHash: hash
                )
            )
        }
        return results.sorted {
            if $0.service == $1.service { return $0.filename < $1.filename }
            return $0.service < $1.service
        }
    }

    private static func isCredentialCandidate(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        let recognizedExtensions = ["env", "p8", "pem", "key", "crt", "cer", "json", "yaml", "yml"]
        return name == ".env"
            || name.contains("credential")
            || name.contains("secret")
            || name.contains("token")
            || name.contains("apikey")
            || recognizedExtensions.contains(ext)
    }

    private static func inferredService(from url: URL) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? "Uncategorized" : parent
    }
}
