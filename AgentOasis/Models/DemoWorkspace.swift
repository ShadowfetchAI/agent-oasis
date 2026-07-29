import Foundation

enum DemoWorkspace {
    static func make(now: Date = Date()) -> WorkspaceState {
        let calendar = Calendar(identifier: .gregorian)
        let apps = makeApps(now: now, calendar: calendar)
        let agents = makeAgents(now: now)
        let ledger = makeLedger(apps: apps, agents: agents, now: now, calendar: calendar)
        let experiments = makeExperiments(apps: apps, now: now, calendar: calendar)
        let connections = [
            ConnectionProfile(
                kind: .appStoreConnect,
                name: "Apple business data",
                status: .needsSetup,
                accessMode: .readOnly,
                endpoint: "api.appstoreconnect.apple.com",
                recordsImported: 0,
                notes: "Add an App Store Connect key or import Sales and Trends reports."
            ),
            ConnectionProfile(
                kind: .hermesFleet,
                name: "Shadowfetch Hermes fleet",
                status: .needsSetup,
                accessMode: .readOnly,
                endpoint: "shadowfetch-linux",
                recordsImported: 0,
                notes: "Read-only SSH telemetry. Credentials are never returned to an agent."
            ),
            ConnectionProfile(
                kind: .delimitedFiles,
                name: "Financial report imports",
                status: .connected,
                accessMode: .importOnly,
                endpoint: "Local files",
                recordsImported: 0,
                notes: "Accepts App Store sales reports and Agent Oasis ledger files."
            ),
            ConnectionProfile(
                kind: .credentialIndex,
                name: "Credential inventory",
                status: .needsSetup,
                accessMode: .readOnly,
                endpoint: "User-selected folder",
                recordsImported: 0,
                notes: "Indexes filenames and permissions without reading secret values."
            )
        ]

        return WorkspaceState(
            name: "Agent Oasis",
            createdAt: now,
            updatedAt: now,
            apps: apps,
            agents: agents,
            ledger: ledger,
            experiments: experiments,
            connections: connections,
            vaultItems: [],
            credentialInventory: [],
            audit: [
                AuditEvent(
                    timestamp: now,
                    category: "Workspace",
                    action: "Created",
                    actor: "Agent Oasis",
                    entityName: "Demo workspace",
                    summary: "Created an encrypted local workspace with sample data.",
                    evidenceHash: "local-demo"
                )
            ],
            settings: WorkspaceSettings()
        )
    }

    private static func makeApps(now: Date, calendar: Calendar) -> [PortfolioApp] {
        let seeds: [(String, String, String, PlatformKind, String, Decimal, Double, [Int], [Double])] = [
            ("Chirphound", "com.realbobcorbin.Chirphound", "CHIRPHOUND-IOS", .iOS, "Reference", 2.99, 0.88, [18, 22, 19, 28, 35, 41], [32, 39, 34, 51, 67, 78]),
            ("Glowmere", "com.realbobcorbin.Glowmere", "GLOWMERE-MAC", .macOS, "Graphics & Design", 4.99, 0.91, [11, 13, 17, 18, 24, 30], [41, 48, 63, 68, 89, 112]),
            ("Speakloft", "com.realbobcorbin.Speakloft", "SPEAKLOFT-IOS", .iOS, "Productivity", 0.99, 0.76, [9, 8, 12, 10, 15, 16], [8, 7, 11, 9, 14, 15]),
            ("Shadowfetch Linux", "com.shadowfetch.linux", "SHADOWFETCH-LINUX", .linux, "Developer Tools", 0, 0.84, [44, 53, 61, 74, 82, 96], [0, 0, 0, 0, 0, 0]),
            ("Dewpoint Rooms", "com.realbobcorbin.DewpointRooms", "DEWPOINT-ROOMS", .iOS, "Weather", 1.99, 0.69, [7, 5, 6, 9, 8, 12], [11, 8, 9, 14, 12, 18])
        ]

        return seeds.map { seed in
            var observations: [AppObservation] = []
            for index in 0..<seed.7.count {
                let monthOffset = -(seed.7.count - 1 - index)
                let date = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
                observations.append(
                    AppObservation(
                        date: date,
                        units: seed.7[index],
                        proceeds: Decimal(seed.8[index]),
                        impressions: seed.7[index] * 118,
                        productPageViews: seed.7[index] * 17,
                        sessions: seed.7[index] * 7,
                        refunds: index % 4 == 0 ? 1 : 0,
                        currency: "USD",
                        source: "Sample data",
                        confidence: .estimated
                    )
                )
            }

            return PortfolioApp(
                name: seed.0,
                bundleID: seed.1,
                sku: seed.2,
                platform: seed.3,
                category: seed.4,
                status: seed.6 > 0.8 ? .healthy : .watch,
                price: seed.5,
                currency: "USD",
                healthScore: seed.6,
                launchedAt: calendar.date(byAdding: .month, value: -11, to: now),
                notes: "Sample portfolio record. Replace with imported live data.",
                observations: observations
            )
        }
    }

    private static func makeAgents(now: Date) -> [AgentProfile] {
        [
            AgentProfile(
                name: "Release Operator",
                role: "Build and submission operations",
                provider: "OpenAI",
                model: "GPT",
                status: .active,
                sessions: 94,
                messages: 2_860,
                acceptedTasks: 86,
                failedTasks: 4,
                reworkedTasks: 9,
                inputTokens: 8_450_000,
                outputTokens: 620_000,
                totalTokensReported: 22_100_000,
                toolCalls: 1_204,
                externalCost: 184,
                computeCost: 26,
                supervisionMinutes: 310,
                equivalentHumanHours: 146,
                loadedHourlyRate: 58,
                directRevenueInfluenced: 640,
                avoidedVendorSpend: 380,
                lastSeen: now,
                source: "Sample data",
                tags: ["iOS", "macOS", "release"],
                    valueBasis: AgentValueBasis(equivalentHumanHours: .measured, loadedHourlyRate: .measured, directRevenueInfluenced: .measured, avoidedVendorSpend: .measured)
            ),
            AgentProfile(
                name: "Kai Kimber",
                role: "Webmaster and publishing",
                provider: "OpenAI",
                model: "GPT",
                status: .active,
                sessions: 138,
                messages: 4_225,
                acceptedTasks: 124,
                failedTasks: 3,
                reworkedTasks: 7,
                inputTokens: 12_800_000,
                outputTokens: 940_000,
                totalTokensReported: 39_200_000,
                toolCalls: 2_086,
                externalCost: 246,
                computeCost: 42,
                supervisionMinutes: 225,
                equivalentHumanHours: 178,
                loadedHourlyRate: 52,
                directRevenueInfluenced: 880,
                avoidedVendorSpend: 720,
                lastSeen: now.addingTimeInterval(-640),
                source: "Sample data",
                tags: ["web", "editorial", "SEO"],
                    valueBasis: AgentValueBasis(equivalentHumanHours: .measured, loadedHourlyRate: .estimated, directRevenueInfluenced: .measured, avoidedVendorSpend: .estimated)
            ),
            AgentProfile(
                name: "Research Analyst",
                role: "Market and product research",
                provider: "Mixed",
                model: "Multiple",
                status: .idle,
                sessions: 67,
                messages: 1_730,
                acceptedTasks: 52,
                failedTasks: 5,
                reworkedTasks: 11,
                inputTokens: 5_200_000,
                outputTokens: 510_000,
                totalTokensReported: 14_900_000,
                toolCalls: 634,
                externalCost: 98,
                computeCost: 14,
                supervisionMinutes: 190,
                equivalentHumanHours: 82,
                loadedHourlyRate: 46,
                directRevenueInfluenced: 210,
                avoidedVendorSpend: 160,
                lastSeen: now.addingTimeInterval(-7_200),
                source: "Sample data",
                tags: ["research", "market"],
                    valueBasis: AgentValueBasis(equivalentHumanHours: .estimated, loadedHourlyRate: .estimated, directRevenueInfluenced: .measured, avoidedVendorSpend: .estimated)
            ),
            AgentProfile(
                name: "Fleet Coordinator",
                role: "Hermes workflow coordination",
                provider: "OpenAI",
                model: "GPT",
                status: .blocked,
                sessions: 59,
                messages: 1_420,
                acceptedTasks: 47,
                failedTasks: 8,
                reworkedTasks: 12,
                inputTokens: 6_100_000,
                outputTokens: 420_000,
                totalTokensReported: 18_700_000,
                toolCalls: 790,
                externalCost: 132,
                computeCost: 22,
                supervisionMinutes: 280,
                equivalentHumanHours: 64,
                loadedHourlyRate: 54,
                directRevenueInfluenced: 120,
                avoidedVendorSpend: 230,
                lastSeen: now.addingTimeInterval(-18_000),
                source: "Sample data",
                tags: ["Hermes", "operations"]
            )
        ]
    }

    private static func makeLedger(
        apps: [PortfolioApp],
        agents: [AgentProfile],
        now: Date,
        calendar: Calendar
    ) -> [LedgerEntry] {
        var entries: [LedgerEntry] = []

        for monthOffset in -5...0 {
            let date = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
            let proceeds = apps.compactMap { app in
                app.observations.min(by: {
                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                })?.proceeds
            }.reduce(Decimal.zero, +)
            entries.append(
                LedgerEntry(
                    date: date,
                    type: .revenue,
                    category: "App sales",
                    entityKind: .business,
                    entityName: "App portfolio",
                    description: "Estimated monthly developer proceeds",
                    amount: proceeds,
                    currency: "USD",
                    source: "Sample data",
                    confidence: .estimated,
                    notes: "Replace with a Sales and Trends import."
                )
            )
            entries.append(
                LedgerEntry(
                    date: date,
                    type: .expense,
                    category: "AI services",
                    entityKind: .business,
                    entityName: "Agent operations",
                    description: "Model and external API costs",
                    amount: Decimal(340 + ((monthOffset + 5) * 19)),
                    currency: "USD",
                    source: "Sample data",
                    confidence: .estimated,
                    notes: ""
                )
            )
        }

        for agent in agents {
            entries.append(
                LedgerEntry(
                    date: now,
                    type: .capacityValue,
                    category: "Agent capacity",
                    entityKind: .agent,
                    entityID: agent.id,
                    entityName: agent.name,
                    description: "Equivalent accepted human work capacity",
                    amount: Decimal(agent.equivalentHumanHours) * agent.loadedHourlyRate,
                    currency: "USD",
                    source: "Sample model",
                    confidence: .inferred,
                    notes: "Capacity value is not the same as realized cash savings."
                )
            )
        }
        return entries
    }

    private static func makeExperiments(
        apps: [PortfolioApp],
        now: Date,
        calendar: Calendar
    ) -> [Experiment] {
        guard apps.count >= 3 else { return [] }
        return [
            Experiment(
                appID: apps[0].id,
                appName: apps[0].name,
                title: "One-time price sensitivity",
                kind: .price,
                status: .running,
                startedAt: calendar.date(byAdding: .day, value: -18, to: now) ?? now,
                hypothesis: "A lower entry price will increase paid conversion enough to raise proceeds.",
                beforeValue: "$2.99",
                afterValue: "$0.99",
                observationWindowDays: 30,
                baselineProceeds: 67,
                observedProceeds: 78,
                confounders: "Recent metadata update and seasonal demand.",
                notes: "Sample experiment. The result is preliminary."
            ),
            Experiment(
                appID: apps[1].id,
                appName: apps[1].name,
                title: "Screenshot narrative refresh",
                kind: .metadata,
                status: .completed,
                startedAt: calendar.date(byAdding: .day, value: -52, to: now) ?? now,
                endedAt: calendar.date(byAdding: .day, value: -22, to: now),
                hypothesis: "Current-version workflow screenshots will improve product page conversion.",
                beforeValue: "2.1%",
                afterValue: "3.4%",
                observationWindowDays: 30,
                baselineProceeds: 68,
                observedProceeds: 112,
                confounders: "A point release landed during the measurement window.",
                notes: "Treat as directional, not causal proof."
            ),
            Experiment(
                appID: apps[2].id,
                appName: apps[2].name,
                title: "Release note positioning",
                kind: .release,
                status: .planned,
                startedAt: calendar.date(byAdding: .day, value: 5, to: now) ?? now,
                hypothesis: "Benefit-first release notes will increase update engagement.",
                beforeValue: "Feature list",
                afterValue: "Outcome-led copy",
                observationWindowDays: 21,
                baselineProceeds: 14,
                observedProceeds: 0,
                confounders: "",
                notes: ""
            )
        ]
    }
}
