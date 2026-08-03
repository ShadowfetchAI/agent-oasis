import AppKit
import Combine
import CryptoKit
import Foundation
import LocalAuthentication

@MainActor
final class OasisStore: ObservableObject {
    enum LockState: Equatable {
        case locked
        case authenticating
        case unlocked
    }

    @Published private(set) var workspace = WorkspaceState.empty
    @Published private(set) var lockState: LockState = .locked
    @Published var selection: AppSection = .commandCenter
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published private(set) var isSyncingHermes = false
    @Published private(set) var isSyncingApple = false

    // Operator UI — command palette, import preview, deep links from Attention Inbox.
    @Published var showingCommandPalette = false
    @Published var showingShortcutsSheet = false
    @Published var showingWhatsNew = false
    @Published var pendingNewItem = false
    @Published var pendingImportURL: URL?
    @Published var pendingImportSummary: ImportSummary?
    @Published var focusedAgentID: UUID?
    @Published var focusedExperimentID: UUID?
    @Published var focusedConnectionID: UUID?

    /// Optional because the app must not die when it cannot create its own storage.
    ///
    /// This used to be non-optional and the initialiser called `fatalError` when
    /// `EncryptedWorkspaceRepository()` threw. On the developer's Mac that never happens. On a
    /// stranger's it can: Application Support locked down by an MDM profile, a full disk, a
    /// home directory on a volume that has gone away, or a sandbox/permission refusal. The
    /// result was an instant crash on launch with no window and no explanation - the worst
    /// possible first contact with a signed binary, and one the user cannot even report
    /// usefully. The app now opens, explains what failed and where, and refuses to pretend it
    /// has a workspace.
    private let repository: EncryptedWorkspaceRepository?

    /// Set when storage could not be created. Non-nil means the app cannot persist anything.
    @Published private(set) var startupFailure: String?

    /// True when the last save failed and the in-memory workspace is ahead of the disk.
    @Published private(set) var hasUnsavedChanges = false

    /// A workspace file exists but cannot be decrypted with this Mac's key.
    ///
    /// Drives the locked-screen recovery route. Distinguishing this from "wrong finger" is
    /// what turns a dead end into a recoverable situation.
    @Published private(set) var workspaceUnreadable = false

    private var key: SymmetricKey?

    var isUnlocked: Bool { lockState == .unlocked }
    var workspaceFilePath: String { repository?.workspaceURL.path ?? "unavailable" }

    /// Storage, or a thrown error describing why there is none.
    ///
    /// Every persistence path goes through this, so a broken install fails loudly at the point
    /// of use with a message a person can act on, instead of silently appearing to work and
    /// losing the day's edits at the next save.
    private func requireRepository() throws -> EncryptedWorkspaceRepository {
        guard let repository else {
            throw WorkspaceSecurityError.storageUnavailable(startupFailure ?? "unknown reason")
        }
        return repository
    }

    /// How the workspace key is obtained.
    ///
    /// Defaults to the real Keychain. Exists so tests can drive the store with a fixed key
    /// against a temporary directory instead of touching the developer's login keychain -
    /// without it, every meaningful test of this 689-line type would either need real Touch ID
    /// or would write to the same Keychain item the running app uses. A test suite that
    /// mutates your actual workspace key is worse than no test suite.
    typealias KeyProvider = (LAContext?) throws -> SymmetricKey

    /// How the device owner is proved present.
    ///
    /// Seamed for the same reason as the key: `unlock()` authenticates BEFORE it loads the
    /// key, so injecting only the key still drives a real Touch ID prompt. Writing the first
    /// test of this type is what surfaced that - the suite sat for 37 seconds waiting on a
    /// biometric dialog no test process can answer. Production passes the real authenticator
    /// and behaves exactly as before.
    typealias OwnerAuthenticator = (String) async throws -> LAContext?

    private let keyProvider: KeyProvider
    private let ownerAuthenticator: OwnerAuthenticator

    init(
        repository: EncryptedWorkspaceRepository? = nil,
        keyProvider: @escaping KeyProvider = { try KeychainService.loadOrCreateKey(context: $0) },
        ownerAuthenticator: @escaping OwnerAuthenticator = {
            try await DeviceOwnerAuthenticator.authenticate(reason: $0)
        }
    ) {
        self.keyProvider = keyProvider
        self.ownerAuthenticator = ownerAuthenticator
        if let repository {
            self.repository = repository
            return
        }
        do {
            self.repository = try EncryptedWorkspaceRepository()
        } catch {
            self.repository = nil
            let support = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false
            ).appendingPathComponent("Agent Oasis").path) ?? "~/Library/Application Support/Agent Oasis"
            self.startupFailure = "Agent Oasis could not create its workspace folder at "
                + "\(support). \(error.localizedDescription) "
                + "Check that the folder is writable, then reopen Agent Oasis."
        }
    }

    /// True when the user simply dismissed the authentication sheet.
    private func isAuthenticationCancellation(_ error: Error) -> Bool {
        guard let laError = error as? LAError else { return false }
        switch laError.code {
        case .userCancel, .systemCancel, .appCancel: return true
        default: return false
        }
    }

    /// Restore an encrypted backup WITHOUT being unlocked first.
    ///
    /// Exists for the one situation the normal restore cannot serve: the workspace on disk is
    /// undecryptable, so there is no way to reach the unlocked state that `restoreBackup`
    /// demands. Requires owner authentication and a recovery key that actually decrypts the
    /// chosen backup, so it grants nothing that was not already granted by holding both.
    func recoverFromBackup(url: URL, recoveryKey: String) async -> Bool {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            _ = try await ownerAuthenticator("Restore an encrypted Agent Oasis backup.")
            let normalized = recoveryKey.components(separatedBy: .whitespacesAndNewlines).joined()
            guard let keyData = Data(base64Encoded: normalized), keyData.count == 32 else {
                throw WorkspaceSecurityError.invalidBackup
            }
            let candidateKey = SymmetricKey(data: keyData)
            let backupData = try Data(contentsOf: url)

            // Prove the backup opens BEFORE touching anything the user still has.
            let restoredState = try WorkspaceCipher.decrypt(
                WorkspaceState.self, from: backupData, using: candidateKey)

            let store = try requireRepository()
            // File first, Keychain second. The reverse order can leave the Keychain holding a
            // key that opens nothing while the only file is sealed under a key that no longer
            // exists anywhere - an unrecoverable lockout produced by the recovery feature.
            _ = try store.restoreEncryptedBackup(backupData, using: candidateKey)
            _ = try KeychainService.replaceKey(with: keyData)

            key = candidateKey
            workspace = restoredState
            lockState = .unlocked
            workspaceUnreadable = false
            appendAudit(
                category: "Backup",
                action: "Recovered from encrypted backup",
                entityName: url.lastPathComponent,
                summary: "Restored an unreadable workspace from an encrypted backup after owner authentication."
            )
            persist()
            noticeMessage = "Workspace recovered from the encrypted backup."
            return true
        } catch {
            if !isAuthenticationCancellation(error) {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    /// Move an undecryptable workspace aside and start fresh, keeping the old bytes.
    ///
    /// Never deletes. The unreadable file may still be recoverable with a key from another
    /// Mac or an older backup, and destroying it to unblock the UI would remove that chance
    /// permanently.
    func setAsideUnreadableWorkspace() async -> Bool {
        do {
            _ = try await ownerAuthenticator("Set aside the unreadable Agent Oasis workspace.")
            let store = try requireRepository()
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let archived = store.workspaceURL
                .deletingLastPathComponent()
                .appendingPathComponent("workspace-unreadable-\(stamp).aovault")
            if FileManager.default.fileExists(atPath: store.workspaceURL.path) {
                try FileManager.default.moveItem(at: store.workspaceURL, to: archived)
            }
            workspaceUnreadable = false
            noticeMessage = "The unreadable workspace was kept at \(archived.lastPathComponent). "
                + "A new empty workspace will be created when you unlock."
            return true
        } catch {
            if !isAuthenticationCancellation(error) {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    func unlock() async {
        guard lockState == .locked else { return }
        lockState = .authenticating
        do {
#if DEBUG
            let bypass = ProcessInfo.processInfo.arguments.contains("--demo-unlocked")
#else
            let bypass = false
#endif
            // The context that proved the owner is present is handed to the Keychain, so the
            // key release is gated by the same authentication rather than merely following it.
            var authContext: LAContext?
            if !bypass {
                authContext = try await ownerAuthenticator(
                    "Unlock your encrypted Agent Oasis workspace."
                )
            }
            let loadedKey = try keyProvider(authContext)
            let store = try requireRepository()
            var loaded = try store.load(using: loadedKey)
            if loaded == nil {
                // Bind it rather than force-unwrapping: `loaded!` was safe by inspection, but
                // a data path should not rely on the reader re-deriving that each time.
                // A NEW WORKSPACE IS EMPTY. It used to be seeded with a full sample
                // portfolio - invented revenue, agent ROI and experiment results - so a
                // stranger's first screen was fabricated financials with nothing marking them
                // as fake. This app exists to tell you which numbers are measured and which
                // are guessed; opening with a screen of neither was indefensible.
                var fresh = WorkspaceState()
                fresh.name = "My Workspace"
                try store.save(fresh, using: loadedKey)
                loaded = fresh
            }
            guard let unwrapped = loaded else {
                throw WorkspaceSecurityError.invalidBackup
            }
            key = loadedKey
            workspace = unwrapped
            lockState = .unlocked
            workspaceUnreadable = false
#if DEBUG
            let unlockSummary = bypass
                ? "Workspace unlocked for local debug validation."
                : "Device owner authenticated."
#else
            let unlockSummary = "Device owner authenticated."
#endif
            appendAudit(
                category: "Security",
                action: "Unlocked",
                entityName: workspace.name,
                summary: unlockSummary
            )
            persist()
        } catch {
            key = nil
            workspace = .empty
            lockState = .locked

            // A workspace that EXISTS but will not decrypt is not a failed login, it is a
            // person locked out of their own records - and until now there was no way back.
            // `restoreBackup` required `isUnlocked`, which this state can never reach, so the
            // encrypted backup the app told them to make was unusable at precisely the moment
            // it was needed.
            //
            // The realistic route here is not a forgotten password. It is Migration Assistant:
            // workspace.aovault travels to the new Mac, the Keychain item does not because it
            // is WhenUnlockedThisDeviceOnly, a fresh key is minted, and AES-GCM authentication
            // fails on a file that is completely intact.
            workspaceUnreadable = (try? requireRepository())
                .map { FileManager.default.fileExists(atPath: $0.workspaceURL.path) } ?? false
                && !isAuthenticationCancellation(error)

            // Deliberately dismissing the biometric sheet must not raise a modal telling the
            // user "Canceled by user." - the app scolding someone for a choice they just made.
            if isAuthenticationCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    func lock(reason: String = "Locked by user") {
        guard isUnlocked else { return }
        appendAudit(
            category: "Security",
            action: "Locked",
            entityName: workspace.name,
            summary: reason
        )
        // DO NOT DISCARD WORK THE DISK NEVER RECEIVED.
        //
        // Auto-lock is not a user decision: it fires from an idle timer, from system sleep and
        // from screen lock. Clearing `workspace` after a failed save meant a full disk or an
        // unmounted volume silently threw away everything since the last good write, with
        // nobody at the keyboard to see the alert. Staying unlocked is the lesser harm - the
        // Mac's own screen lock is already protecting the screen in the cases that matter.
        guard persist() else {
            errorMessage = "Agent Oasis could not save your workspace, so it stayed unlocked "
                + "rather than discard unsaved changes. Free some space or reconnect the "
                + "drive, then export a backup from the Vault."
            return
        }
        key = nil
        workspace = .empty
        lockState = .locked
        selection = .commandCenter
    }

    func mutate(
        category: String,
        action: String,
        entityName: String,
        summary: String,
        _ change: (inout WorkspaceState) -> Void
    ) {
        guard isUnlocked else {
            errorMessage = WorkspaceSecurityError.workspaceLocked.localizedDescription
            return
        }
        change(&workspace)
        workspace.updatedAt = Date()
        appendAudit(
            category: category,
            action: action,
            entityName: entityName,
            summary: summary
        )
        persist()
    }

    func addLedgerEntry(_ entry: LedgerEntry) {
        mutate(
            category: "Ledger",
            action: "Entry added",
            entityName: entry.entityName,
            summary: "\(entry.type.title) record added from \(entry.source)."
        ) {
            $0.ledger.append(entry)
        }
    }

    func addApp(_ app: PortfolioApp) {
        mutate(
            category: "Portfolio",
            action: "App added",
            entityName: app.name,
            summary: "Added \(app.platform.rawValue) portfolio record."
        ) {
            $0.apps.append(app)
        }
    }

    func updateApp(_ app: PortfolioApp) {
        mutate(
            category: "Portfolio",
            action: "App updated",
            entityName: app.name,
            summary: "Updated portfolio settings and notes."
        ) { state in
            guard let index = state.apps.firstIndex(where: { $0.id == app.id }) else { return }
            state.apps[index] = app
        }
    }

    func addAgent(_ agent: AgentProfile) {
        mutate(
            category: "Agent",
            action: "Agent added",
            entityName: agent.name,
            summary: "Added an agent economics profile."
        ) {
            $0.agents.append(agent)
        }
    }

    func updateAgent(_ agent: AgentProfile) {
        mutate(
            category: "Agent",
            action: "Economics updated",
            entityName: agent.name,
            summary: "Updated cost, capacity, and attribution assumptions."
        ) { state in
            guard let index = state.agents.firstIndex(where: { $0.id == agent.id }) else { return }
            state.agents[index] = agent
        }
    }

    /// Clones an agent for a new variant without inventing evidence.
    ///
    /// Telemetry counters reset to zero and provenance becomes all-estimated with a
    /// "Manual duplicate" source. Copying measured Hermes figures as if they applied to a
    /// new profile would be fabrication wearing a Duplicate button.
    @discardableResult
    func duplicateAgent(_ agent: AgentProfile) -> AgentProfile {
        var copy = agent
        copy.id = UUID()
        copy.name = agent.name.hasSuffix(" copy") ? agent.name : "\(agent.name) copy"
        copy.status = .idle
        copy.sessions = 0
        copy.messages = 0
        copy.acceptedTasks = 0
        copy.failedTasks = 0
        copy.reworkedTasks = 0
        copy.inputTokens = 0
        copy.outputTokens = 0
        copy.totalTokensReported = 0
        copy.toolCalls = 0
        copy.lastSeen = nil
        copy.source = "Manual duplicate"
        copy.valueBasis = .allEstimated
        addAgent(copy)
        focusedAgentID = copy.id
        selection = .agents
        noticeMessage = "Duplicated \(agent.name). Telemetry reset; value inputs marked estimated."
        return copy
    }

    func addExperiment(_ experiment: Experiment) {
        mutate(
            category: "Experiment",
            action: "Experiment added",
            entityName: experiment.title,
            summary: "Created a \(experiment.kind.rawValue) experiment for \(experiment.appName)."
        ) {
            $0.experiments.append(experiment)
        }
    }

    func updateExperiment(_ experiment: Experiment) {
        mutate(
            category: "Experiment",
            action: "Experiment updated",
            entityName: experiment.title,
            summary: "Updated status to \(experiment.status.rawValue)."
        ) { state in
            guard let index = state.experiments.firstIndex(where: { $0.id == experiment.id }) else { return }
            state.experiments[index] = experiment
        }
    }

    /// Clones an experiment as a new planned run with a fresh observation window.
    @discardableResult
    func duplicateExperiment(_ experiment: Experiment) -> Experiment {
        var copy = experiment
        copy.id = UUID()
        copy.title = experiment.title.hasSuffix(" copy") ? experiment.title : "\(experiment.title) copy"
        copy.status = .planned
        copy.startedAt = Date()
        copy.endedAt = nil
        copy.observedProceeds = 0
        copy.afterValue = ""
        copy.confounders = ""
        addExperiment(copy)
        focusedExperimentID = copy.id
        selection = .experiments
        noticeMessage = "Duplicated \(experiment.title) as a new planned experiment."
        return copy
    }

    func updateConnection(_ connection: ConnectionProfile) {
        mutate(
            category: "Connection",
            action: "Connection updated",
            entityName: connection.name,
            summary: "Updated \(connection.accessMode.title.lowercased()) connector configuration."
        ) { state in
            guard let index = state.connections.firstIndex(where: { $0.id == connection.id }) else {
                return
            }
            state.connections[index] = connection
        }
    }

    func addVaultItem(_ item: VaultItem) {
        mutate(
            category: "Vault",
            action: "Secret stored",
            entityName: item.label,
            summary: "Stored a \(item.kind.rawValue) for \(item.service). Secret value was not logged."
        ) {
            $0.vaultItems.append(item)
        }
    }

    func deleteVaultItem(id: UUID) {
        guard let item = workspace.vaultItems.first(where: { $0.id == id }) else { return }
        mutate(
            category: "Vault",
            action: "Secret removed",
            entityName: item.label,
            summary: "Removed the encrypted record. Secret value was not logged."
        ) {
            $0.vaultItems.removeAll { $0.id == id }
            for index in $0.connections.indices where $0.connections[index].secretItemID == id {
                $0.connections[index].secretItemID = nil
                $0.connections[index].status = .needsSetup
            }
            for index in $0.connections.indices
            where $0.connections[index].configuration["salesSecretItemID"] == id.uuidString {
                $0.connections[index].configuration["salesSecretItemID"] = nil
                $0.connections[index].status = .needsSetup
            }
        }
    }

    func importData(from url: URL) {
        beginImportPreview(from: url)
    }

    /// Stages an import so the operator can confirm counts before any write.
    func beginImportPreview(from url: URL) {
        guard isUnlocked else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let summary = try ImportExportService.previewDelimitedFile(at: url, against: workspace)
            pendingImportURL = url
            pendingImportSummary = summary
        } catch {
            pendingImportURL = nil
            pendingImportSummary = nil
            errorMessage = error.localizedDescription
        }
    }

    func cancelImportPreview() {
        pendingImportURL = nil
        pendingImportSummary = nil
    }

    func confirmImportPreview() {
        guard isUnlocked, let url = pendingImportURL else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            var copy = workspace
            let result = try ImportExportService.importDelimitedFile(at: url, into: &copy)
            workspace = copy
            workspace.updatedAt = Date()
            appendAudit(
                category: "Import",
                action: "Data imported",
                entityName: url.lastPathComponent,
                summary: result.message
            )
            persist()
            noticeMessage = result.message
            pendingImportURL = nil
            pendingImportSummary = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func navigate(to section: AppSection) {
        guard isUnlocked else { return }
        selection = section
    }

    func runCommandAction(_ name: String) {
        guard isUnlocked else { return }
        switch name {
        case "new":
            requestNewItem()
        case "import":
            requestImportPicker()
        case "export-ledger":
            exportLedgerCSV()
        case "export-portfolio":
            exportPortfolioCSV()
        case "export-backup":
            exportBackup()
        case "export-brief":
            exportExecutiveBrief()
        case "lock":
            lock(reason: "Locked by command palette")
        case "shortcuts":
            showingShortcutsSheet = true
        case "whats-new":
            showingWhatsNew = true
        default:
            break
        }
    }

    /// Context-aware create: opens the add sheet for the section that can create, or Agents.
    func requestNewItem() {
        switch selection {
        case .portfolio, .agents, .ledger, .experiments:
            pendingNewItem = true
        case .commandCenter, .hermesFleet, .decisionLab, .connections, .vault, .audit, .settings:
            selection = .agents
            pendingNewItem = true
        }
    }

    func requestImportPicker() {
        let panel = NSOpenPanel()
        panel.title = "Import Agent Oasis Data"
        panel.message = "Choose a Sales and Trends or ledger CSV/TSV. You will preview counts before anything is written."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = []
        guard panel.runModal() == .OK, let url = panel.url else { return }
        beginImportPreview(from: url)
    }

    func openAttentionItem(_ item: AttentionItem) {
        switch item.destination {
        case .section(let section):
            selection = section
        case .agent(let id):
            focusedAgentID = id
            selection = .agents
        case .experiment(let id):
            focusedExperimentID = id
            selection = .experiments
        case .connection(let id):
            focusedConnectionID = id
            selection = .connections
        }
    }

    func markReleaseNotesSeen(_ version: String) {
        guard isUnlocked else { return }
        var settings = workspace.settings
        settings.lastSeenReleaseNotes = version
        updateSettings(settings, workspaceName: workspace.name)
    }

    var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "3.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0.0"
    }

    func shouldShowWhatsNewOnUnlock() -> Bool {
        workspace.settings.lastSeenReleaseNotes != marketingVersion
    }

    func exportBackup() {
        guard isUnlocked else { return }
        let panel = NSSavePanel()
        panel.title = "Export Encrypted Agent Oasis Backup"
        panel.nameFieldStringValue = "Agent-Oasis-\(Self.fileDateFormatter.string(from: Date())).oasisbackup"
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // runModal spins a nested run loop in NSModalPanelRunLoopMode, which belongs to
        // .common - so the idle timer, sleep and screen-lock handlers all run INSIDE this
        // call and lock() can complete between the guard above and the write below. Without
        // re-checking, a locked app still writes the plaintext it prepared before the panel
        // opened, and the audit row recording that export is appended into an emptied
        // workspace and lost at the next unlock.
        guard isUnlocked, key != nil else {
            errorMessage = WorkspaceSecurityError.workspaceLocked.localizedDescription
            return
        }
        do {
            let data = try requireRepository().encryptedBackupData()
            try data.write(to: url, options: .atomic)
            appendAudit(
                category: "Backup",
                action: "Encrypted backup exported",
                entityName: url.lastPathComponent,
                summary: "Exported encrypted workspace data. No plaintext data was written."
            )
            persist()
            noticeMessage = "Encrypted backup saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreBackup(from url: URL, recoveryKey: String) async -> Bool {
        guard isUnlocked, key != nil else { return false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            _ = try await ownerAuthenticator("Restore an encrypted Agent Oasis backup.")
            let normalized = recoveryKey
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            guard let keyData = Data(base64Encoded: normalized), keyData.count == 32 else {
                throw WorkspaceSecurityError.invalidBackup
            }
            let backupData = try Data(contentsOf: url)
            let candidateKey = SymmetricKey(data: keyData)

            _ = try WorkspaceCipher.decrypt(
                WorkspaceState.self,
                from: backupData,
                using: candidateKey
            )

            // The workspace can auto-lock while this function is suspended in the biometric
            // prompt: RootView drives lock from a timer, sleep and screen-lock, all on the
            // main actor, which is free to run during the await. Without re-checking, the
            // continuation would repopulate `key` and `workspace` behind a lock screen the
            // user believes is protecting them.
            guard isUnlocked, key != nil else {
                throw WorkspaceSecurityError.workspaceLocked
            }

            // FILE FIRST, KEYCHAIN SECOND.
            //
            // The reverse order was a lockout generator: if the file write failed (disk full,
            // volume detached) the Keychain already held the BACKUP's key while the workspace
            // on disk was still sealed under the ORIGINAL key - which existed nowhere else.
            // The compensating write was `try?`, so its own failure was discarded silently and
            // the next launch met an undecryptable workspace with no explanation.
            //
            // Writing the file first means a Keychain failure leaves a readable file and a
            // stale key, which the rollback below can still repair - and if even that fails,
            // the recovery route on the locked screen can finish the job.
            let restored = try requireRepository().restoreEncryptedBackup(
                backupData,
                using: candidateKey
            )
            do {
                _ = try KeychainService.replaceKey(with: keyData)
            } catch {
                // The file is now the backup's, so the key must follow or nothing opens.
                // Report rather than swallow: this is the state the user has to know about.
                errorMessage = "The backup was restored but this Mac's key could not be "
                    + "updated. Keep your recovery key: you may need it to reopen Agent Oasis."
                throw error
            }
            key = candidateKey
            workspace = restored

            workspace.updatedAt = Date()
            appendAudit(
                category: "Backup",
                action: "Encrypted backup restored",
                entityName: url.lastPathComponent,
                summary: "Validated and restored encrypted workspace data after owner authentication."
            )
            persist()
            noticeMessage = "Encrypted backup restored."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func exportLedgerCSV() {
        exportCSV(
            suggestedName: "Agent-Oasis-Ledger-\(Self.fileDateFormatter.string(from: Date())).csv",
            data: ImportExportService.ledgerCSV(from: workspace),
            entityName: "Ledger"
        )
    }

    func exportPortfolioCSV() {
        exportCSV(
            suggestedName: "Agent-Oasis-Portfolio-\(Self.fileDateFormatter.string(from: Date())).csv",
            data: ImportExportService.portfolioCSV(from: workspace),
            entityName: "Portfolio"
        )
    }

    func captureBusinessSnapshot(label: String? = nil) {
        let name = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "Checkpoint \(Date().formatted(date: .abbreviated, time: .shortened))"
        let snapshot = DecisionEngine.makeSnapshot(
            label: name?.isEmpty == false ? name! : fallback,
            state: workspace
        )
        mutate(
            category: "Decision",
            action: "Business checkpoint captured",
            entityName: snapshot.label,
            summary: "Captured cash, portfolio, agent, and evidence measures without vault contents."
        ) { state in
            var snapshots = state.businessSnapshots ?? []
            snapshots.append(snapshot)
            state.businessSnapshots = snapshots
        }
        noticeMessage = "Business checkpoint captured."
    }

    func deleteBusinessSnapshot(id: UUID) {
        guard let snapshot = workspace.snapshots.first(where: { $0.id == id }) else { return }
        mutate(
            category: "Decision",
            action: "Business checkpoint removed",
            entityName: snapshot.label,
            summary: "Removed a point-in-time summary; source ledger and observations were unchanged."
        ) { state in
            state.businessSnapshots?.removeAll { $0.id == id }
        }
    }

    func exportExecutiveBrief() {
        let html = ExecutiveBriefingService.html(for: workspace)
        exportPlaintextDocument(
            suggestedName: "Agent-Oasis-Brief-\(Self.fileDateFormatter.string(from: Date())).html",
            data: Data(html.utf8),
            title: "Executive Brief",
            format: "self-contained HTML"
        )
    }

    func recoveryKeyString() -> String? {
        guard let key else { return nil }
        return key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    func scanCredentialInventory(folder: URL) async {
        guard isUnlocked else { return }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer {
            if accessed { folder.stopAccessingSecurityScopedResource() }
        }
        do {
            let items = try await Task.detached(priority: .userInitiated) {
                try CredentialInventoryService.scan(folder: folder)
            }.value
            mutate(
                category: "Vault",
                action: "Credential inventory scanned",
                entityName: folder.lastPathComponent,
                summary: "Indexed \(items.count) filenames and permission records without reading secret values."
            ) { state in
                state.credentialInventory = items
                if let index = state.connections.firstIndex(where: { $0.kind == .credentialIndex }) {
                    state.connections[index].status = .connected
                    state.connections[index].lastSync = Date()
                    state.connections[index].recordsImported = items.count
                    state.connections[index].endpoint = folder.lastPathComponent
                }
            }
            noticeMessage = "\(items.count) credential metadata records indexed."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncHermesFleet() async {
        guard isUnlocked, !isSyncingHermes else { return }
        isSyncingHermes = true
        defer { isSyncingHermes = false }
        do {
            let snapshot = try await HermesFleetService.fetchFleetSnapshot(
                host: workspace.settings.remoteHermesHost,
                profilesPath: workspace.settings.hermesProfilesPath,
                toolsPath: workspace.settings.hermesToolsPath,
                statePath: workspace.settings.hermesStatePath,
                gatewayUnitPattern: workspace.settings.hermesGatewayUnitPattern
            )
            mutate(
                category: "Connection",
                action: "Hermes fleet synchronized",
                entityName: workspace.settings.remoteHermesHost,
                summary: "Read \(snapshot.agents.count) profiles and \(snapshot.activeGateways) active gateways."
            ) { state in
                state.hermesFleetSnapshot = snapshot

                for remote in snapshot.agents {
                    if let index = state.agents.firstIndex(where: {
                        Self.normalizedAgentName($0.name) == Self.normalizedAgentName(remote.name)
                    }) {
                        state.agents[index].status = remote.isGatewayActive ? .active : .offline
                        state.agents[index].sessions = remote.sessions
                        state.agents[index].messages = remote.messages
                        state.agents[index].toolCalls = remote.toolCalls
                        state.agents[index].inputTokens = remote.inputTokens
                        state.agents[index].outputTokens = remote.outputTokens
                        state.agents[index].totalTokensReported = remote.totalTokensReported
                        state.agents[index].lastSeen = snapshot.fetchedAt
                        state.agents[index].source = "Live Hermes telemetry"
                    } else {
                        state.agents.append(
                            AgentProfile(
                                name: Self.displayName(remote.name),
                                role: "Hermes agent",
                                provider: "Unassigned",
                                model: "Unassigned",
                                status: remote.isGatewayActive ? .active : .offline,
                                sessions: remote.sessions,
                                messages: remote.messages,
                                acceptedTasks: 0,
                                failedTasks: 0,
                                reworkedTasks: 0,
                                inputTokens: remote.inputTokens,
                                outputTokens: remote.outputTokens,
                                totalTokensReported: remote.totalTokensReported,
                                toolCalls: remote.toolCalls,
                                externalCost: 0,
                                computeCost: 0,
                                supervisionMinutes: 0,
                                equivalentHumanHours: 0,
                                loadedHourlyRate: 0,
                                directRevenueInfluenced: 0,
                                avoidedVendorSpend: 0,
                                lastSeen: snapshot.fetchedAt,
                                source: "Live Hermes telemetry",
                                tags: ["Hermes"]
                            )
                        )
                    }
                }

                if let index = state.connections.firstIndex(where: { $0.kind == .hermesFleet }) {
                    state.connections[index].status = .connected
                    state.connections[index].lastSync = snapshot.fetchedAt
                    state.connections[index].recordsImported = snapshot.agents.count
                    state.connections[index].endpoint = state.settings.remoteHermesHost
                    let kanban = Self.conciseHermesSummary(snapshot.kanbanSummary)
                    state.connections[index].notes = [
                        "\(snapshot.version).",
                        "\(snapshot.activeGateways)/\(snapshot.profileCount) gateways active.",
                        kanban
                    ]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                }
            }
            noticeMessage = "Hermes fleet synchronized without reading credentials."
        } catch {
            if let index = workspace.connections.firstIndex(where: { $0.kind == .hermesFleet }) {
                workspace.connections[index].status = .error
                workspace.connections[index].lastSync = Date()
                workspace.connections[index].notes = error.localizedDescription
                persist()
            }
            errorMessage = error.localizedDescription
        }
    }

    func syncAppStoreConnect() async {
        guard isUnlocked, !isSyncingApple else { return }
        guard let connection = workspace.connections.first(where: {
            $0.kind == .appStoreConnect
        }) else {
            errorMessage = "No App Store Connect connection is configured."
            return
        }
        let appKeyID = connection.configuration["keyID", default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let appSecret = connection.secretItemID.flatMap { secretID in
            workspace.vaultItems.first(where: { $0.id == secretID })
        }
        let salesSecretID = connection.configuration["salesSecretItemID"]
            .flatMap(UUID.init(uuidString:))
        let salesSecret = salesSecretID.flatMap { secretID in
            workspace.vaultItems.first(where: { $0.id == secretID })
        } ?? appSecret
        let salesKeyID = connection.configuration["salesKeyID", default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSalesKeyID = salesSecretID == nil && salesKeyID.isEmpty
            ? appKeyID
            : salesKeyID
        let vendorNumber = connection.configuration["vendorNumber", default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let canSyncApps = appSecret != nil && !appKeyID.isEmpty
        let canSyncSales = salesSecret != nil
            && !effectiveSalesKeyID.isEmpty
            && !vendorNumber.isEmpty
        guard canSyncApps || canSyncSales else {
            errorMessage = "Configure an app-record key or a Sales and Reports key with a Vendor Number."
            return
        }

        isSyncingApple = true
        defer { isSyncingApple = false }
        var records: [AppStoreAppRecord]?
        var salesReport: AppStoreSalesReport?
        var failures: [String] = []

        if canSyncApps, let appSecret {
            do {
                records = try await AppStoreConnectConnector.fetchApps(
                    issuerID: connection.configuration["issuerID", default: ""],
                    keyID: appKeyID,
                    privateKeyPEM: appSecret.secret
                )
            } catch {
                failures.append("App records: \(error.localizedDescription)")
            }
        }

        if canSyncSales, let salesSecret {
            do {
                let explicitIssuer = connection.configuration["salesIssuerID", default: ""]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                salesReport = try await AppStoreConnectConnector.fetchLatestDailySalesReport(
                    issuerID: salesSecretID == nil && explicitIssuer.isEmpty
                        ? connection.configuration["issuerID", default: ""]
                        : explicitIssuer,
                    keyID: effectiveSalesKeyID,
                    privateKeyPEM: salesSecret.secret,
                    vendorNumber: vendorNumber
                )
            } catch {
                failures.append("Sales report: \(error.localizedDescription)")
            }
        }

        guard records != nil || salesReport != nil else {
            if let index = workspace.connections.firstIndex(where: { $0.id == connection.id }) {
                workspace.connections[index].status = .error
                workspace.connections[index].lastSync = Date()
                workspace.connections[index].notes = failures.joined(separator: " ")
                appendAudit(
                    category: "Connection",
                    action: "App Store Connect sync failed",
                    entityName: connection.name,
                    summary: "Read-only app and sales requests failed. No secret value was logged."
                )
                persist()
            }
            errorMessage = failures.joined(separator: "\n")
            return
        }

        let syncedAt = Date()
        var importedSales: ImportSummary?
        var importFailure: String?
        mutate(
            category: "Connection",
            action: "App Store Connect synchronized",
            entityName: connection.name,
            summary: "Synchronized app records and available daily sales evidence."
        ) { state in
            if let records {
                for record in records {
                    if let index = state.apps.firstIndex(where: {
                        // Both arms must require a non-empty identifier. The sku arm already
                        // did; the bundleID arm did not, so a locally created app with a blank
                        // bundleID matched ANY incoming record that also had one - and then
                        // absorbed its name, bundleID and sku while keeping its own
                        // observations and ledger history. That silently re-attaches one app's
                        // financial record to a different app.
                        (!$0.bundleID.isEmpty && !record.bundleID.isEmpty
                            && $0.bundleID.caseInsensitiveCompare(record.bundleID) == .orderedSame)
                            || (!$0.sku.isEmpty && !record.sku.isEmpty
                                && $0.sku.caseInsensitiveCompare(record.sku) == .orderedSame)
                    }) {
                        state.apps[index].name = record.name
                        state.apps[index].bundleID = record.bundleID
                        state.apps[index].sku = record.sku
                    } else {
                        state.apps.append(
                            PortfolioApp(
                                name: record.name,
                                bundleID: record.bundleID,
                                sku: record.sku,
                                platform: .iOS,
                                category: "Uncategorized",
                                status: .watch,
                                price: 0,
                                currency: state.settings.baseCurrency,
                                healthScore: 0.5,
                                launchedAt: nil,
                                notes: "Live App Store Connect record. Confirm platform and category.",
                                observations: []
                            )
                        )
                    }
                }
            }

            if let salesReport {
                do {
                    importedSales = try ImportExportService.importDelimitedText(
                        salesReport.text,
                        sourceName: salesReport.sourceName,
                        into: &state
                    )
                } catch {
                    importFailure = error.localizedDescription
                }
            }

            if let index = state.connections.firstIndex(where: { $0.id == connection.id }) {
                let recordCount = records?.count ?? 0
                let salesCount = importedSales?.totalRecords ?? 0
                let allFailures = failures + [importFailure].compactMap { $0 }
                state.connections[index].status = allFailures.isEmpty ? .connected : .stale
                state.connections[index].lastSync = syncedAt
                state.connections[index].recordsImported = recordCount + salesCount
                var notes: [String] = []
                if records != nil { notes.append("\(recordCount) app records reconciled.") }
                if let importedSales {
                    notes.append("Latest daily sales: \(importedSales.observationsAdded) observations, \(importedSales.ledgerEntriesAdded) cash entries.")
                }
                notes.append(contentsOf: allFailures)
                state.connections[index].notes = notes.joined(separator: " ")
            }
        }

        let appCount = records?.count ?? 0
        let salesCount = importedSales?.observationsAdded ?? 0
        noticeMessage = "App Store Connect synced \(appCount) apps and \(salesCount) daily sales observations."
        let allFailures = failures + [importFailure].compactMap { $0 }
        if !allFailures.isEmpty {
            errorMessage = "Partial sync completed.\n" + allFailures.joined(separator: "\n")
        }
    }

    func updateSettings(_ settings: WorkspaceSettings, workspaceName: String) {
        mutate(
            category: "Settings",
            action: "Workspace settings updated",
            entityName: workspaceName,
            summary: "Updated local workspace preferences."
        ) {
            $0.settings = settings
            $0.name = workspaceName
        }
    }

    /// Erase everything and start over with an empty workspace.
    ///
    /// Was `resetToDemo`, which replaced the user's records with fabricated ones. It also
    /// destroyed the vault - App Store Connect private keys that may exist nowhere else - and
    /// the entire audit history, in place, with no snapshot. The pre-erase copy below is what
    /// makes this recoverable instead of final.
    func eraseWorkspace() {
        guard isUnlocked, let key else { return }

        // Keep what is being destroyed. A one-click action that removes private keys and the
        // whole audit trail must not be irreversible.
        if let store = try? requireRepository(),
           let existing = try? Data(contentsOf: store.workspaceURL) {
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let snapshot = store.workspaceURL
                .deletingLastPathComponent()
                .appendingPathComponent("workspace-before-erase-\(stamp).aovault")
            try? existing.write(to: snapshot, options: [.atomic])
        }

        var fresh = WorkspaceState()
        fresh.name = workspace.name
        fresh.settings = workspace.settings
        workspace = fresh
        appendAudit(
            category: "Workspace",
            action: "Erased",
            entityName: workspace.name,
            summary: "Replaced the workspace with an empty one. A pre-erase copy was kept "
                + "beside it, encrypted with the same key."
        )
        _ = key
        persist()
        noticeMessage = "Workspace erased. A copy of the previous contents was kept beside it."
    }

    private func exportCSV(suggestedName: String, data: Data, entityName: String) {
        guard isUnlocked else { return }
        let panel = NSSavePanel()
        panel.title = "Export \(entityName) CSV"
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // runModal spins a nested run loop in NSModalPanelRunLoopMode, which belongs to
        // .common - so the idle timer, sleep and screen-lock handlers all run INSIDE this
        // call and lock() can complete between the guard above and the write below. Without
        // re-checking, a locked app still writes the plaintext it prepared before the panel
        // opened, and the audit row recording that export is appended into an emptied
        // workspace and lost at the next unlock.
        guard isUnlocked, key != nil else {
            errorMessage = WorkspaceSecurityError.workspaceLocked.localizedDescription
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            appendAudit(
                category: "Export",
                action: "CSV exported",
                entityName: entityName,
                summary: "Exported user-requested plaintext CSV to \(url.lastPathComponent)."
            )
            persist()
            noticeMessage = "\(entityName) CSV saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportPlaintextDocument(
        suggestedName: String,
        data: Data,
        title: String,
        format: String
    ) {
        guard isUnlocked else { return }
        let panel = NSSavePanel()
        panel.title = "Export \(title)"
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard isUnlocked, key != nil else {
            errorMessage = WorkspaceSecurityError.workspaceLocked.localizedDescription
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            appendAudit(
                category: "Export",
                action: "Executive brief exported",
                entityName: title,
                summary: "Exported user-requested \(format) without vault items or secret values."
            )
            persist()
            noticeMessage = "\(title) saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Timestamp format used by the audit chain.
    ///
    /// Must match what is PERSISTED. WorkspaceCipher encodes dates as ISO-8601 to second
    /// precision, so hashing a full-precision `timeIntervalSince1970` produced a digest that
    /// stopped matching the moment the workspace round-tripped through disk.
    private static let auditStampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// The digest for one audit entry, chained to the entry before it.
    ///
    /// TWO THINGS WERE WRONG WITH THE OLD VERSION, and both made the value decorative while
    /// it was rendered in monospace beside financial records, where it reads as proof.
    ///
    /// 1. `Date()` was called twice - once inside the digest input and once for the stored
    ///    timestamp - so the value hashed was microseconds away from the value saved. Nobody,
    ///    including this app, could ever recompute it. It was unverifiable by construction.
    /// 2. Nothing linked an entry to its predecessor, so any entry could be deleted or
    ///    reordered and every remaining digest still checked out. A per-row hash with no chain
    ///    detects a rewritten row and nothing else.
    ///
    /// Chaining the previous hash means removing or reordering any entry breaks every digest
    /// after it, which is what "tamper-evident" has to mean to be worth printing.
    static func auditDigest(
        previousHash: String,
        timestamp: Date,
        category: String,
        action: String,
        actor: String,
        entityName: String,
        summary: String
    ) -> String {
        let stamp = auditStampFormatter.string(from: timestamp)
        let input = [previousHash, stamp, category, action, actor, entityName, summary]
            .joined(separator: "\u{1F}")   // unit separator: cannot occur in these fields
        return SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Recompute the whole chain and return the index of the first entry that does not verify.
    ///
    /// Returns nil when the trail is intact. This is what makes the hash a claim the user can
    /// check rather than a decoration.
    static func firstBrokenAuditIndex(in audit: [AuditEvent]) -> Int? {
        var previous = ""
        for (index, event) in audit.enumerated() {
            let expected = auditDigest(
                previousHash: previous,
                timestamp: event.timestamp,
                category: event.category,
                action: event.action,
                actor: event.actor,
                entityName: event.entityName,
                summary: event.summary
            )
            if expected != event.evidenceHash { return index }
            previous = event.evidenceHash
        }
        return nil
    }

    private func appendAudit(
        category: String,
        action: String,
        entityName: String,
        summary: String
    ) {
        // ONE `now`, used for both the digest and the stored timestamp.
        let now = Date()
        let actor = NSFullUserName().isEmpty ? "Device owner" : NSFullUserName()
        let digest = Self.auditDigest(
            previousHash: workspace.audit.last?.evidenceHash ?? "",
            timestamp: now,
            category: category,
            action: action,
            actor: actor,
            entityName: entityName,
            summary: summary
        )
        workspace.audit.append(
            AuditEvent(
                timestamp: now,
                category: category,
                action: action,
                actor: actor,
                entityName: entityName,
                summary: summary,
                evidenceHash: digest
            )
        )
    }

    /// Write the workspace. Returns false when the save did not land.
    ///
    /// This used to return Void and turn every write error into a transient banner, so
    /// `lock()` could not tell a failed save from a good one and cleared `key` and
    /// `workspace` regardless. Auto-lock is not a user action - it fires from a 30s idle
    /// timer, from `willSleepNotification` and from screen lock - so on a full disk or an
    /// unmounted volume an hour of edits was discarded with nobody present to read the alert.
    @discardableResult
    private func persist() -> Bool {
        guard let key else { return false }
        do {
            try requireRepository().save(workspace, using: key)
        } catch {
            errorMessage = "Agent Oasis could not save the encrypted workspace: \(error.localizedDescription)"
        }
        hasUnsavedChanges = false
        return true
    }

    private static func normalizedAgentName(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func displayName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static func conciseHermesSummary(_ value: String) -> String {
        let statusOnly = value
            .components(separatedBy: "By assignee:")
            .first ?? value
        let collapsed = statusOnly
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard collapsed.count > 180 else { return collapsed }
        return String(collapsed.prefix(177)) + "..."
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
