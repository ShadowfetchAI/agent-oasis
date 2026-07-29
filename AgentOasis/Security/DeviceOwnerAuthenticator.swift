import Foundation
import LocalAuthentication

enum DeviceOwnerAuthenticator {
    /// Authenticate the device owner and return the CONTEXT that proved it.
    ///
    /// Returning the context is the whole point. Previously this function proved the owner
    /// was present and then threw that proof away, and the workspace key was fetched from the
    /// Keychain separately with no reference to it. The gate protected the window, not the
    /// key: any process running as the user could read the key directly and decrypt the
    /// workspace without ever meeting Touch ID.
    ///
    /// Handing the authenticated `LAContext` to `KeychainService` lets the Keychain itself
    /// require user presence, which makes the gate cryptographic rather than advisory - and
    /// it keeps the user to ONE prompt instead of two.
    @discardableResult
    static func authenticate(reason: String) async throws -> LAContext {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Mac Password"
        // The proof stays usable just long enough to unlock; it is not a session.
        context.touchIDAuthenticationAllowableReuseDuration = 10

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? WorkspaceSecurityError.authenticationUnavailable
        }

        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        )
        guard success else { throw WorkspaceSecurityError.authenticationFailed }
        return context
    }
}
