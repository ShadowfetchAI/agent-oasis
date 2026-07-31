import SwiftUI

/// A single action the operator can run without leaving the keyboard.
struct OasisCommand: Identifiable, Hashable {
    enum Kind: Hashable {
        case navigate(AppSection)
        case action(String)
    }

    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let shortcut: String?
    let keywords: [String]
    let kind: Kind
}

enum OasisCommandCatalog {
    static func all() -> [OasisCommand] {
        var commands: [OasisCommand] = []

        for (index, section) in AppSection.allCases.enumerated() {
            let key = index < 9 ? "⌘\(index + 1)" : nil
            commands.append(
                OasisCommand(
                    id: "go-\(section.rawValue)",
                    title: "Go to \(section.title)",
                    subtitle: "Open the \(section.title.lowercased()) section",
                    systemImage: section.systemImage,
                    shortcut: key,
                    keywords: [section.title, section.rawValue, "go", "navigate", "section"],
                    kind: .navigate(section)
                )
            )
        }

        commands.append(contentsOf: [
            OasisCommand(
                id: "new-item",
                title: "New…",
                subtitle: "Add an agent, ledger entry, or experiment for the current section",
                systemImage: "plus.circle",
                shortcut: "⌘N",
                keywords: ["new", "add", "create", "agent", "ledger", "experiment"],
                kind: .action("new")
            ),
            OasisCommand(
                id: "import",
                title: "Import report",
                subtitle: "Preview a Sales and Trends or ledger CSV/TSV before writing",
                systemImage: "square.and.arrow.down",
                shortcut: "⌘I",
                keywords: ["import", "csv", "tsv", "sales", "upload"],
                kind: .action("import")
            ),
            OasisCommand(
                id: "export-ledger",
                title: "Export ledger CSV",
                subtitle: "Plaintext spreadsheet of cash and modelled ledger rows",
                systemImage: "tablecells",
                shortcut: "⌘E",
                keywords: ["export", "csv", "ledger", "download"],
                kind: .action("export-ledger")
            ),
            OasisCommand(
                id: "export-portfolio",
                title: "Export portfolio CSV",
                subtitle: "Plaintext spreadsheet of apps and latest observations",
                systemImage: "square.grid.2x2",
                shortcut: nil,
                keywords: ["export", "csv", "portfolio", "apps"],
                kind: .action("export-portfolio")
            ),
            OasisCommand(
                id: "export-backup",
                title: "Export encrypted backup",
                subtitle: "Write an .oasisbackup that needs the recovery key",
                systemImage: "externaldrive.badge.plus",
                shortcut: nil,
                keywords: ["backup", "export", "encrypted", "recovery"],
                kind: .action("export-backup")
            ),
            OasisCommand(
                id: "lock",
                title: "Lock Agent Oasis",
                subtitle: "Require Touch ID or Mac password to reopen",
                systemImage: "lock.fill",
                shortcut: "⌘⇧L",
                keywords: ["lock", "secure", "privacy"],
                kind: .action("lock")
            ),
            OasisCommand(
                id: "shortcuts",
                title: "Keyboard shortcuts",
                subtitle: "Show the cheat sheet",
                systemImage: "keyboard",
                shortcut: "⌘/",
                keywords: ["shortcuts", "keyboard", "help", "cheat"],
                kind: .action("shortcuts")
            ),
            OasisCommand(
                id: "whats-new",
                title: "What’s new",
                subtitle: "Release notes for this build",
                systemImage: "sparkles",
                shortcut: nil,
                keywords: ["changelog", "release", "notes", "version"],
                kind: .action("whats-new")
            )
        ])

        return commands
    }

    static func matching(_ query: String) -> [OasisCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = all()
        guard !trimmed.isEmpty else { return all }
        let tokens = trimmed.lowercased().split(separator: " ").map(String.init)
        return all.filter { command in
            let haystack = ([command.title, command.subtitle] + command.keywords)
                .joined(separator: " ")
                .lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
}

struct CommandPaletteView: View {
    @EnvironmentObject private var store: OasisStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var queryFocused: Bool

    private var results: [OasisCommand] {
        OasisCommandCatalog.matching(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Jump to a section or run an action…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($queryFocused)
                    .onSubmit { runFirst() }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            Divider()

            if results.isEmpty {
                Text("No matching commands")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { command in
                    Button {
                        run(command)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: command.systemImage)
                                .foregroundStyle(OasisPalette.teal)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(command.title)
                                    .font(.body.weight(.medium))
                                Text(command.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let shortcut = command.shortcut {
                                Text(shortcut)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }

            Divider()
            HStack {
                Text("↑↓ to browse · Return to run · Esc to close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘K")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .frame(width: 560, height: 420)
        .onAppear { queryFocused = true }
    }

    private func runFirst() {
        guard let first = results.first else { return }
        run(first)
    }

    private func run(_ command: OasisCommand) {
        dismiss()
        // Defer so the sheet can tear down before another sheet or navigation change.
        DispatchQueue.main.async {
            switch command.kind {
            case .navigate(let section):
                store.navigate(to: section)
            case .action(let name):
                store.runCommandAction(name)
            }
        }
    }
}
