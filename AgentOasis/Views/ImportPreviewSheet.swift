import SwiftUI
import UniformTypeIdentifiers

/// Shows what an import would write before any workspace mutation.
///
/// Imports used to land immediately from the file picker. Previewing keeps the idempotent
/// path honest: the operator sees how many apps, observations and ledger rows would land,
/// and can cancel without touching disk.
struct ImportPreviewSheet: View {
    @EnvironmentObject private var store: OasisStore
    @Environment(\.dismiss) private var dismiss

    let url: URL
    let summary: ImportSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import preview")
                        .font(.title2.weight(.semibold))
                    Text(url.lastPathComponent)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Cancel") {
                    store.cancelImportPreview()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Text("Nothing has been written yet. Confirming applies the same idempotent importer used by the toolbar — re-importing the same sales rows will not double-count revenue.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
                spacing: 12
            ) {
                previewTile(
                    title: "Apps created",
                    value: "\(summary.appsCreated)",
                    systemImage: "square.grid.2x2",
                    color: OasisPalette.teal
                )
                previewTile(
                    title: "Observations",
                    value: "\(summary.observationsAdded)",
                    systemImage: "chart.bar",
                    color: OasisPalette.green
                )
                previewTile(
                    title: "Ledger rows",
                    value: "\(summary.ledgerEntriesAdded)",
                    systemImage: "list.bullet.rectangle",
                    color: OasisPalette.indigo
                )
                previewTile(
                    title: "Total records",
                    value: "\(summary.totalRecords)",
                    systemImage: "checkmark.seal",
                    color: OasisPalette.gold
                )
            }

            if summary.totalRecords == 0 {
                Label(
                    "This file is recognized but would add no new rows (likely already imported).",
                    systemImage: "info.circle"
                )
                .foregroundStyle(OasisPalette.gold)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    store.cancelImportPreview()
                    dismiss()
                }
                Button("Import \(summary.totalRecords) record\(summary.totalRecords == 1 ? "" : "s")") {
                    store.confirmImportPreview()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(summary.totalRecords == 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func previewTile(
        title: String,
        value: String,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title.weight(.semibold).monospacedDigit())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oasisSurface(corner: OasisMetrics.tightCorner, elevated: false)
    }
}

struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let highlights: [(String, String, String)] = [
        (
            "scope",
            "Decision Lab",
            "Rank portfolio and agent decisions from evidence, compare rolling periods, and keep the rationale beside every recommendation."
        ),
        (
            "apple.logo",
            "Direct App Store sales",
            "Sync the latest daily Summary Sales report with a read-only key and Vendor Number. Imported proceeds become confirmed observations and cash ledger entries."
        ),
        (
            "slider.horizontal.3",
            "Scenario Studio",
            "Test price, volume, proceeds, refunds, costs, and labor assumptions. Net cash and modelled capacity are calculated separately and never combined."
        ),
        (
            "camera.metering.matrix",
            "Business checkpoints",
            "Capture point-in-time cash, portfolio, agent, and evidence measures before a release, price change, or staffing decision, then compare them with today."
        ),
        (
            "doc.richtext",
            "Executive briefs",
            "Export a self-contained, print-ready HTML report that ranks decisions and states its evidence limits. Vault items and secret values are excluded."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What’s new in 2.0")
                        .font(.title2.weight(.semibold))
                    Text("Decision Intelligence — from keeping records to making defensible calls.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Continue") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(highlights, id: \.1) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.0)
                                .foregroundStyle(OasisPalette.teal)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.1)
                                    .font(.headline)
                                Text(item.2)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 600, height: 520)
    }
}
