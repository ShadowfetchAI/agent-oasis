import Foundation

enum AppSection: String, CaseIterable, Identifiable, Codable {
    case commandCenter
    case portfolio
    case agents
    case ledger
    case experiments
    case connections
    case vault
    case audit
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandCenter: "Command Center"
        case .portfolio: "Portfolio"
        case .agents: "Agents"
        case .ledger: "Ledger"
        case .experiments: "Experiments"
        case .connections: "Connections"
        case .vault: "Vault"
        case .audit: "Audit"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .commandCenter: "gauge.with.dots.needle.67percent"
        case .portfolio: "square.grid.2x2"
        case .agents: "cpu"
        case .ledger: "list.bullet.rectangle"
        case .experiments: "flask"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .vault: "lock.shield"
        case .audit: "checkmark.seal"
        case .settings: "gearshape"
        }
    }
}

enum PlatformKind: String, Codable, CaseIterable, Identifiable {
    case iOS
    case macOS
    case linux
    case web
    case other

    var id: String { rawValue }
}

enum LifecycleStatus: String, Codable, CaseIterable, Identifiable {
    case healthy
    case watch
    case attention
    case paused
    case archived

    var id: String { rawValue }
}

enum DataConfidence: String, Codable, CaseIterable, Identifiable {
    case confirmed
    case estimated
    case inferred
    case unknown

    var id: String { rawValue }

    var score: Double {
        switch self {
        case .confirmed: 1
        case .estimated: 0.75
        case .inferred: 0.5
        case .unknown: 0.2
        }
    }
}

struct AppObservation: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var units: Int
    var proceeds: Decimal
    var impressions: Int?
    var productPageViews: Int?
    var sessions: Int?
    var refunds: Int?
    var currency: String
    var source: String
    var confidence: DataConfidence
}

struct PortfolioApp: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var bundleID: String
    var sku: String
    var platform: PlatformKind
    var category: String
    var status: LifecycleStatus
    var price: Decimal
    var currency: String
    var healthScore: Double
    var launchedAt: Date?
    var notes: String
    var observations: [AppObservation]

    var latestObservation: AppObservation? {
        observations.max(by: { $0.date < $1.date })
    }

    var priorObservation: AppObservation? {
        observations.sorted(by: { $0.date > $1.date }).dropFirst().first
    }
}

enum AgentStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case idle
    case blocked
    case offline

    var id: String { rawValue }
}

struct AgentProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var role: String
    var provider: String
    var model: String
    var status: AgentStatus
    var sessions: Int
    var messages: Int
    var acceptedTasks: Int
    var failedTasks: Int
    var reworkedTasks: Int
    var inputTokens: Int64
    var outputTokens: Int64
    var totalTokensReported: Int64
    var toolCalls: Int
    var externalCost: Decimal
    var computeCost: Decimal
    var supervisionMinutes: Int
    var equivalentHumanHours: Double
    var loadedHourlyRate: Decimal
    var directRevenueInfluenced: Decimal
    var avoidedVendorSpend: Decimal
    var lastSeen: Date?
    var source: String
    var tags: [String]
}

enum LedgerEntryType: String, Codable, CaseIterable, Identifiable {
    case revenue
    case expense
    case cashSavings
    case capacityValue
    case riskAvoidance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .revenue: "Revenue"
        case .expense: "Expense"
        case .cashSavings: "Cash Savings"
        case .capacityValue: "Capacity Value"
        case .riskAvoidance: "Risk Avoidance"
        }
    }
}

enum LedgerEntityKind: String, Codable, CaseIterable, Identifiable {
    case app
    case agent
    case business
    case linux
    case website
    case other

    var id: String { rawValue }
}

struct LedgerEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var type: LedgerEntryType
    var category: String
    var entityKind: LedgerEntityKind
    var entityID: UUID?
    var entityName: String
    var description: String
    var amount: Decimal
    var currency: String
    var source: String
    var confidence: DataConfidence
    var evidenceReference: String?
    var notes: String
}

enum ExperimentStatus: String, Codable, CaseIterable, Identifiable {
    case planned
    case running
    case completed
    case inconclusive

    var id: String { rawValue }
}

enum ExperimentKind: String, Codable, CaseIterable, Identifiable {
    case price
    case release
    case metadata
    case marketing
    case product
    case operations

    var id: String { rawValue }
}

struct Experiment: Identifiable, Codable, Hashable {
    var id = UUID()
    var appID: UUID?
    var appName: String
    var title: String
    var kind: ExperimentKind
    var status: ExperimentStatus
    var startedAt: Date
    var endedAt: Date?
    var hypothesis: String
    var beforeValue: String
    var afterValue: String
    var observationWindowDays: Int
    var baselineProceeds: Decimal
    var observedProceeds: Decimal
    var confounders: String
    var notes: String
}

enum ConnectionKind: String, Codable, CaseIterable, Identifiable {
    case appStoreConnect
    case hermesFleet
    case delimitedFiles
    case credentialIndex
    case manual
    case website
    case linux

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appStoreConnect: "App Store Connect"
        case .hermesFleet: "Hermes Fleet"
        case .delimitedFiles: "CSV / TSV Imports"
        case .credentialIndex: "Credential Index"
        case .manual: "Manual Ledger"
        case .website: "Website Analytics"
        case .linux: "Linux Telemetry"
        }
    }
}

enum ConnectionStatus: String, Codable, CaseIterable, Identifiable {
    case connected
    case needsSetup
    case stale
    case error
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connected: "Connected"
        case .needsSetup: "Needs Setup"
        case .stale: "Needs Sync"
        case .error: "Error"
        case .disabled: "Disabled"
        }
    }
}

enum AccessMode: String, Codable, CaseIterable, Identifiable {
    case readOnly
    case readWrite
    case importOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readOnly: "Read only"
        case .readWrite: "Read and write"
        case .importOnly: "Import only"
        }
    }
}

struct ConnectionProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: ConnectionKind
    var name: String
    var status: ConnectionStatus
    var accessMode: AccessMode
    var endpoint: String
    var lastSync: Date?
    var recordsImported: Int
    var secretItemID: UUID?
    var notes: String
    var configuration: [String: String] = [:]
}

extension ConnectionProfile {
    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case status
        case accessMode
        case endpoint
        case lastSync
        case recordsImported
        case secretItemID
        case notes
        case configuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(ConnectionKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(ConnectionStatus.self, forKey: .status)
        accessMode = try container.decode(AccessMode.self, forKey: .accessMode)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        lastSync = try container.decodeIfPresent(Date.self, forKey: .lastSync)
        recordsImported = try container.decodeIfPresent(Int.self, forKey: .recordsImported) ?? 0
        secretItemID = try container.decodeIfPresent(UUID.self, forKey: .secretItemID)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        configuration = try container.decodeIfPresent(
            [String: String].self,
            forKey: .configuration
        ) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(status, forKey: .status)
        try container.encode(accessMode, forKey: .accessMode)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encodeIfPresent(lastSync, forKey: .lastSync)
        try container.encode(recordsImported, forKey: .recordsImported)
        try container.encodeIfPresent(secretItemID, forKey: .secretItemID)
        try container.encode(notes, forKey: .notes)
        try container.encode(configuration, forKey: .configuration)
    }
}

enum VaultItemKind: String, Codable, CaseIterable, Identifiable {
    case apiKey
    case privateKey
    case token
    case password
    case account
    case recovery

    var id: String { rawValue }
}

struct VaultItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var service: String
    var account: String
    var kind: VaultItemKind
    var secret: String
    var createdAt: Date
    var updatedAt: Date
    var notes: String

    var maskedHint: String {
        guard !secret.isEmpty else { return "No value" }
        let suffix = String(secret.suffix(min(4, secret.count)))
        return "Stored securely - ends in \(suffix)"
    }
}

struct CredentialInventoryItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var filename: String
    var service: String
    var fileSize: Int64
    var posixPermissions: String
    var modifiedAt: Date?
    var indexedAt: Date
    var sourcePathHash: String
}

struct AuditEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var timestamp: Date
    var category: String
    var action: String
    var actor: String
    var entityName: String
    var summary: String
    var evidenceHash: String
}

struct WorkspaceSettings: Codable, Hashable {
    var baseCurrency = "USD"
    var autoLockMinutes = 15
    var remoteHermesHost = "shadowfetch-linux"
    var showCapacityValueInHeadline = false
    var includeDemoData = true
}

struct WorkspaceState: Codable, Hashable {
    var schemaVersion = 1
    var workspaceID = UUID()
    var name = "Agent Oasis"
    var createdAt = Date()
    var updatedAt = Date()
    var apps: [PortfolioApp] = []
    var agents: [AgentProfile] = []
    var ledger: [LedgerEntry] = []
    var experiments: [Experiment] = []
    var connections: [ConnectionProfile] = []
    var vaultItems: [VaultItem] = []
    var credentialInventory: [CredentialInventoryItem] = []
    var audit: [AuditEvent] = []
    var settings = WorkspaceSettings()

    static var empty: WorkspaceState {
        WorkspaceState(name: "Locked Workspace")
    }
}
