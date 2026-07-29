import AppKit
import Combine
import CryptoKit
import Foundation

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

    private let repository: EncryptedWorkspaceRepository
    private var key: SymmetricKey?

    var isUnlocked: Bool { lockState == .unlocked }
    var workspaceFilePath: String { repository.workspaceURL.path }

    init(repository: EncryptedWorkspaceRepository? = nil) {
        do {
            self.repository = try repository ?? EncryptedWorkspaceRepository()
        } catch {
            fatalError("Agent Oasis cannot create its local workspace: \(error)")
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
            if !bypass {
                try await DeviceOwnerAuthenticator.authenticate(
                    reason: "Unlock your encrypted Agent Oasis workspace."
                )
            }
            let loadedKey = try KeychainService.loadOrCreateKey()
            var loaded = try repository.load(using: loadedKey)
            if loaded == nil {
                loaded = DemoWorkspace.make()
                try repository.save(loaded!, using: loadedKey)
            }
            key = loadedKey
            workspace = loaded!
            lockState = .unlocked
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
        persist()
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
        }
    }

    func importData(from url: URL) {
        guard isUnlocked else { return }
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportBackup() {
        guard isUnlocked else { return }
        let panel = NSSavePanel()
        panel.title = "Export Encrypted Agent Oasis Backup"
        panel.nameFieldStringValue = "Agent-Oasis-\(Self.fileDateFormatter.string(from: Date())).oasisbackup"
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try repository.encryptedBackupData()
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
        guard isUnlocked, let currentKey = key else { return false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            try await DeviceOwnerAuthenticator.authenticate(
                reason: "Restore an encrypted Agent Oasis backup."
            )
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

            let currentKeyData = currentKey.withUnsafeBytes { Data($0) }
            do {
                _ = try KeychainService.replaceKey(with: keyData)
                let restored = try repository.restoreEncryptedBackup(
                    backupData,
                    using: candidateKey
                )
                key = candidateKey
                workspace = restored
            } catch {
                _ = try? KeychainService.replaceKey(with: currentKeyData)
                throw error
            }

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
            let snapshot = try await HermesConnector.fetchFleetSnapshot(
                host: workspace.settings.remoteHermesHost
            )
            mutate(
                category: "Connection",
                action: "Hermes fleet synchronized",
                entityName: workspace.settings.remoteHermesHost,
                summary: "Read \(snapshot.agents.count) profiles and \(snapshot.activeGateways) active gateways."
            ) { state in
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
        guard let secretID = connection.secretItemID,
              let secret = workspace.vaultItems.first(where: { $0.id == secretID }) else {
            errorMessage = "Select an App Store Connect .p8 key from the encrypted vault."
            return
        }

        isSyncingApple = true
        defer { isSyncingApple = false }
        do {
            let records = try await AppStoreConnectConnector.fetchApps(
                issuerID: connection.configuration["issuerID", default: ""],
                keyID: connection.configuration["keyID", default: ""],
                privateKeyPEM: secret.secret
            )
            let syncedAt = Date()
            mutate(
                category: "Connection",
                action: "App Store Connect synchronized",
                entityName: connection.name,
                summary: "Read and reconciled \(records.count) App Store app records."
            ) { state in
                for record in records {
                    if let index = state.apps.firstIndex(where: {
                        $0.bundleID.caseInsensitiveCompare(record.bundleID) == .orderedSame
                            || (!$0.sku.isEmpty
                                && $0.sku.caseInsensitiveCompare(record.sku) == .orderedSame)
                    }) {
                        state.apps[index].name = record.name
                        state.apps[index].bundleID = record.bundleID
                        state.apps[index].sku = record.sku
                        if state.apps[index].notes.contains("Sample portfolio record") {
                            state.apps[index].notes =
                                "Live App Store Connect record. Import Sales and Trends data to add financial observations."
                        }
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
                                notes: "Live App Store Connect record. Confirm platform and import Sales and Trends data for financial observations.",
                                observations: []
                            )
                        )
                    }
                }

                if let index = state.connections.firstIndex(where: {
                    $0.id == connection.id
                }) {
                    state.connections[index].status = .connected
                    state.connections[index].lastSync = syncedAt
                    state.connections[index].recordsImported = records.count
                    state.connections[index].notes =
                        "Live read-only app-record sync. Financial data remains report-imported."
                }
            }
            noticeMessage = "\(records.count) App Store app records synchronized."
        } catch {
            if let index = workspace.connections.firstIndex(where: {
                $0.id == connection.id
            }) {
                workspace.connections[index].status = .error
                workspace.connections[index].lastSync = Date()
                workspace.connections[index].notes = error.localizedDescription
                appendAudit(
                    category: "Connection",
                    action: "App Store Connect sync failed",
                    entityName: connection.name,
                    summary: "The read-only request failed. No secret value was logged."
                )
                persist()
            }
            errorMessage = error.localizedDescription
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

    func resetToDemo() {
        guard isUnlocked else { return }
        let reset = DemoWorkspace.make()
        workspace = reset
        appendAudit(
            category: "Workspace",
            action: "Reset",
            entityName: reset.name,
            summary: "Replaced the current workspace with a fresh sample workspace."
        )
        persist()
        noticeMessage = "Sample workspace restored."
    }

    private func exportCSV(suggestedName: String, data: Data, entityName: String) {
        guard isUnlocked else { return }
        let panel = NSSavePanel()
        panel.title = "Export \(entityName) CSV"
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
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

    private func appendAudit(
        category: String,
        action: String,
        entityName: String,
        summary: String
    ) {
        let digestInput = "\(Date().timeIntervalSince1970)|\(category)|\(action)|\(entityName)|\(summary)"
        let digest = SHA256.hash(data: Data(digestInput.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        workspace.audit.append(
            AuditEvent(
                timestamp: Date(),
                category: category,
                action: action,
                actor: NSFullUserName().isEmpty ? "Device owner" : NSFullUserName(),
                entityName: entityName,
                summary: summary,
                evidenceHash: digest
            )
        )
    }

    private func persist() {
        guard let key else { return }
        do {
            try repository.save(workspace, using: key)
        } catch {
            errorMessage = "Agent Oasis could not save the encrypted workspace: \(error.localizedDescription)"
        }
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
