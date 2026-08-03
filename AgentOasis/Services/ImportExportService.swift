import Foundation

struct ImportSummary: Equatable {
    var sourceName: String
    var appsCreated: Int
    var observationsAdded: Int
    var ledgerEntriesAdded: Int

    var totalRecords: Int {
        appsCreated + observationsAdded + ledgerEntriesAdded
    }

    var message: String {
        "\(totalRecords) records imported from \(sourceName)"
    }
}

enum ImportExportError: LocalizedError {
    case unreadableFile
    case unsupportedFormat
    case noRecognizedRows

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "Agent Oasis could not read the selected file."
        case .unsupportedFormat: "Use a CSV or TSV sales report or Agent Oasis ledger file."
        case .noRecognizedRows: "No recognized App Store or ledger rows were found."
        }
    }
}

enum ImportExportService {
    /// Runs the importer against a copy of `state` so the UI can show counts before writing.
    static func previewDelimitedFile(
        at url: URL,
        against state: WorkspaceState
    ) throws -> ImportSummary {
        var copy = state
        return try importDelimitedFile(at: url, into: &copy)
    }

    static func previewDelimitedText(
        _ text: String,
        sourceName: String,
        against state: WorkspaceState
    ) throws -> ImportSummary {
        var copy = state
        return try importDelimitedText(text, sourceName: sourceName, into: &copy)
    }

    static func importDelimitedFile(
        at url: URL,
        into state: inout WorkspaceState
    ) throws -> ImportSummary {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw ImportExportError.unreadableFile
        }
        return try importDelimitedText(text, sourceName: url.lastPathComponent, into: &state)
    }

    static func importDelimitedText(
        _ text: String,
        sourceName: String,
        into state: inout WorkspaceState
    ) throws -> ImportSummary {
        let rows = DelimitedTextParser.parse(text)
        guard !rows.isEmpty else { throw ImportExportError.noRecognizedRows }

        let headerKeys = Set(rows[0].keys.map(normalizedKey))
        if headerKeys.contains("developerproceeds") || headerKeys.contains("units") && headerKeys.contains("title") {
            return importAppStoreRows(rows, sourceName: sourceName, into: &state)
        }
        if headerKeys.contains("amount") && headerKeys.contains("type") {
            return importLedgerRows(rows, sourceName: sourceName, into: &state)
        }
        throw ImportExportError.noRecognizedRows
    }

    static func ledgerCSV(from state: WorkspaceState) -> Data {
        var lines = ["date,type,category,entity,description,amount,currency,source,confidence,notes"]
        let formatter = ISO8601DateFormatter()
        for entry in state.ledger.sorted(by: { $0.date < $1.date }) {
            lines.append([
                formatter.string(from: entry.date),
                entry.type.rawValue,
                entry.category,
                entry.entityName,
                entry.description,
                NSDecimalNumber(decimal: entry.amount).stringValue,
                entry.currency,
                entry.source,
                entry.confidence.rawValue,
                entry.notes
            ].map(csvEscape).joined(separator: ","))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func portfolioCSV(from state: WorkspaceState) -> Data {
        var lines = ["app,bundle_id,sku,platform,status,price,currency,latest_units,latest_proceeds,health"]
        for app in state.apps.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            lines.append([
                app.name,
                app.bundleID,
                app.sku,
                app.platform.rawValue,
                app.status.rawValue,
                NSDecimalNumber(decimal: app.price).stringValue,
                app.currency,
                String(app.latestObservation?.units ?? 0),
                NSDecimalNumber(decimal: app.latestObservation?.proceeds ?? 0).stringValue,
                String(format: "%.2f", app.healthScore)
            ].map(csvEscape).joined(separator: ","))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func importAppStoreRows(
        _ rows: [[String: String]],
        sourceName: String,
        into state: inout WorkspaceState
    ) -> ImportSummary {
        var appsCreated = 0
        var observationsAdded = 0
        var ledgerAdded = 0
        let calendar = Calendar(identifier: .gregorian)
        let keys = Set(rows.first?.keys.map(normalizedKey) ?? [])
        // In Apple's real Summary Sales report, Developer Proceeds is PER UNIT. Earlier
        // Agent Oasis example files used the same heading for a pre-calculated row total.
        // The official report can be identified by its Provider and Product Type fields, so
        // both formats remain compatible without silently multiplying legacy imports.
        let isOfficialAppleSummary = keys.contains("provider")
            && keys.contains("producttypeidentifier")
        let grouped = Dictionary(grouping: rows) { row in
            value(in: row, keys: ["SKU", "Title", "App Name", "Apple Identifier"]) ?? "Imported App"
        }

        for (identity, appRows) in grouped {
            let first = appRows[0]
            let name = value(in: first, keys: ["Title", "App Name"]) ?? identity
            let sku = value(in: first, keys: ["SKU"]) ?? identity
            let bundleID = value(in: first, keys: ["Bundle ID", "Bundle Identifier"])
                ?? "imported.\(slug(name))"

            let appIndex: Int
            if let existing = state.apps.firstIndex(where: {
                (!$0.sku.isEmpty && $0.sku.caseInsensitiveCompare(sku) == .orderedSame)
                    || $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) {
                appIndex = existing
            } else {
                state.apps.append(
                    PortfolioApp(
                        name: name,
                        bundleID: bundleID,
                        sku: sku,
                        platform: .iOS,
                        category: "Imported",
                        status: .watch,
                        price: decimal(value(in: first, keys: ["Customer Price"])) ?? 0,
                        currency: value(in: first, keys: ["Customer Currency", "Currency of Proceeds"]) ?? "USD",
                        healthScore: 0.6,
                        notes: "Created from \(sourceName).",
                        observations: []
                    )
                )
                appIndex = state.apps.count - 1
                appsCreated += 1
            }

            let byDateAndCurrency = Dictionary(grouping: appRows) { row in
                AppStoreObservationGroup(
                    date: parseDate(value(in: row, keys: ["Begin Date", "End Date", "Date"]))
                        ?? Date(),
                    currency: value(
                        in: row,
                        keys: ["Currency of Proceeds", "Customer Currency"]
                    ) ?? "USD"
                )
            }
            for (group, dateRows) in byDateAndCurrency {
                let date = group.date
                let units = dateRows.reduce(0) {
                    $0 + decimalUnits(value(in: $1, keys: ["Units"]))
                }
                let proceeds = dateRows.reduce(Decimal.zero) {
                    let amount = decimal(value(in: $1, keys: ["Developer Proceeds", "Proceeds"])) ?? 0
                    if isOfficialAppleSummary,
                       value(in: $1, keys: ["Developer Proceeds"]) != nil {
                        return $0 + amount * Decimal(decimalUnits(value(in: $1, keys: ["Units"])))
                    }
                    return $0 + amount
                }
                let currency = group.currency
                // IDEMPOTENT BY (app, day, source). The previous version appended
                // unconditionally, so importing the same monthly Sales and Trends file twice -
                // a re-download, a retry after a mis-click, the same file kept in two folders -
                // doubled reported revenue. AnalyticsEngine sums state.ledger directly, so the
                // headline figure doubled with it, silently and permanently.
                let observation = AppObservation(
                    date: date,
                    units: units,
                    proceeds: proceeds,
                    currency: currency,
                    source: sourceName,
                    confidence: .confirmed
                )
                if let existing = state.apps[appIndex].observations.firstIndex(where: {
                    $0.source == sourceName
                        && $0.currency.caseInsensitiveCompare(currency) == .orderedSame
                        && calendar.isDate($0.date, inSameDayAs: date)
                }) {
                    // A corrected re-export of the same day should REPLACE, not accumulate.
                    state.apps[appIndex].observations[existing] = observation
                } else {
                    state.apps[appIndex].observations.append(observation)
                    observationsAdded += 1
                }

                let appID = state.apps[appIndex].id
                let entry = LedgerEntry(
                    date: date,
                    type: .revenue,
                    category: "App sales",
                    entityKind: .app,
                    entityID: appID,
                    entityName: state.apps[appIndex].name,
                    description: "Developer proceeds from imported report",
                    amount: proceeds,
                    currency: currency,
                    source: sourceName,
                    confidence: .confirmed,
                    notes: "Imported alongside \(units) reported units."
                )
                if let existing = state.ledger.firstIndex(where: {
                    $0.entityID == appID && $0.source == sourceName
                        && $0.category == "App sales"
                        && $0.currency.caseInsensitiveCompare(currency) == .orderedSame
                        && calendar.isDate($0.date, inSameDayAs: date)
                }) {
                    state.ledger[existing] = entry
                } else {
                    state.ledger.append(entry)
                    ledgerAdded += 1
                }
            }
        }

        return ImportSummary(
            sourceName: sourceName,
            appsCreated: appsCreated,
            observationsAdded: observationsAdded,
            ledgerEntriesAdded: ledgerAdded
        )
    }

    private static func importLedgerRows(
        _ rows: [[String: String]],
        sourceName: String,
        into state: inout WorkspaceState
    ) -> ImportSummary {
        var added = 0
        for row in rows {
            guard
                let amount = decimal(value(in: row, keys: ["amount"])),
                let rawType = value(in: row, keys: ["type"]),
                let type = LedgerEntryType(rawValue: normalizedKey(rawType))
                    ?? LedgerEntryType.allCases.first(where: {
                        normalizedKey($0.title) == normalizedKey(rawType)
                    })
            else { continue }

            state.ledger.append(
                LedgerEntry(
                    date: parseDate(value(in: row, keys: ["date"])) ?? Date(),
                    type: type,
                    category: value(in: row, keys: ["category"]) ?? "Imported",
                    entityKind: .other,
                    entityName: value(in: row, keys: ["entity", "entity_name"]) ?? "Imported",
                    description: value(in: row, keys: ["description"]) ?? "Imported record",
                    amount: amount,
                    currency: value(in: row, keys: ["currency"]) ?? state.settings.baseCurrency,
                    source: sourceName,
                    confidence: DataConfidence(rawValue: normalizedKey(
                        value(in: row, keys: ["confidence"]) ?? ""
                    )) ?? .confirmed,
                    notes: value(in: row, keys: ["notes"]) ?? ""
                )
            )
            added += 1
        }

        return ImportSummary(
            sourceName: sourceName,
            appsCreated: 0,
            observationsAdded: 0,
            ledgerEntriesAdded: added
        )
    }

    private static func value(in row: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let match = row.first(where: { normalizedKey($0.key) == normalizedKey(key) })?.value,
               !match.isEmpty {
                return match
            }
        }
        return nil
    }

    private static func normalizedKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func decimal(_ value: String?) -> Decimal? {
        guard let value else { return nil }
        let sanitized = value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: sanitized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func decimalUnits(_ value: String?) -> Int {
        guard let decimalValue = decimal(value) else { return 0 }
        return NSDecimalNumber(decimal: decimalValue).intValue
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        for format in ["MM/dd/yyyy", "yyyy-MM-dd", "MM/dd/yy", "MMM d, yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func slug(_ value: String) -> String {
        value.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

private struct AppStoreObservationGroup: Hashable {
    let date: Date
    let currency: String
}
