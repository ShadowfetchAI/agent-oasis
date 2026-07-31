import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let groups: [(String, [(String, String)])] = [
        ("Navigation", [
            ("⌘1", "Command Center"),
            ("⌘2", "Portfolio"),
            ("⌘3", "Agents"),
            ("⌘4", "Ledger"),
            ("⌘5", "Experiments"),
            ("⌘6", "Connections"),
            ("⌘7", "Vault"),
            ("⌘8", "Audit"),
            ("⌘9", "Settings")
        ]),
        ("Actions", [
            ("⌘K", "Command palette"),
            ("⌘N", "New item in current section"),
            ("⌘I", "Import report (with preview)"),
            ("⌘E", "Export ledger CSV"),
            ("⌘⇧L", "Lock Agent Oasis"),
            ("⌘/", "This shortcuts sheet")
        ]),
        ("Tips", [
            ("Drop CSV/TSV", "Onto Command Center or Ledger to preview import"),
            ("Right-click", "Agents and experiments for Duplicate"),
            ("Attention Inbox", "Command Center lists only actionable gaps")
        ])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard shortcuts")
                        .font(.title2.weight(.semibold))
                    Text("Operator-speed navigation without leaving the keyboard.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.0)
                                .font(.headline)
                            ForEach(group.1, id: \.0) { row in
                                HStack {
                                    Text(row.0)
                                        .font(.body.monospaced())
                                        .foregroundStyle(OasisPalette.teal)
                                        .frame(width: 110, alignment: .leading)
                                    Text(row.1)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 480)
    }
}
