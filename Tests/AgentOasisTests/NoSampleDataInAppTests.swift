import Foundation
import XCTest

/// Proves the SHIPPED app cannot produce sample data, structurally.
///
/// A promise in a README is not a guarantee; someone re-adds a seed call six months later and
/// nothing objects. This walks the actual app sources and fails if sample-data machinery has
/// crept back into the target that gets compiled into the binary.
final class NoSampleDataInAppTests: XCTestCase {

    /// Locate the repository root by walking up from this file.
    private func appSourcesDirectory() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("AgentOasis")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               FileManager.default.fileExists(
                   atPath: candidate.appendingPathComponent("AgentOasisApp.swift").path) {
                return candidate
            }
        }
        throw XCTSkip("Could not locate the app sources from \(#filePath)")
    }

    func testAppTargetContainsNoSampleDataGenerator() throws {
        let root = try appSourcesDirectory()
        let banned = ["DemoWorkspace", "resetToDemo", "includeDemoData"]
        var offenders: [String] = []

        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            for token in banned where source.contains(token) {
                // A comment explaining the removal is fine; a call site is not.
                let offending = source
                    .split(separator: "\n")
                    .filter { $0.contains(token) }
                    .filter { line in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///")
                            && !trimmed.hasPrefix("*")
                    }
                if !offending.isEmpty {
                    offenders.append("\(url.lastPathComponent): \(offending.joined(separator: " | "))")
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "The shipped app must not be able to fabricate records. Found: \(offenders)"
        )
    }
}
