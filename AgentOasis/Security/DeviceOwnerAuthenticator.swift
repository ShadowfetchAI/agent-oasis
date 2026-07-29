import Foundation
import LocalAuthentication

enum DeviceOwnerAuthenticator {
    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Mac Password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? WorkspaceSecurityError.authenticationUnavailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            guard success else { throw WorkspaceSecurityError.authenticationFailed }
        } catch {
            throw error
        }
    }
}
