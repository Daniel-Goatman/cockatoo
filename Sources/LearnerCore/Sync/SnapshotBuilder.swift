import Foundation

/// Builds the versioned active slice the extension renders from. Library
/// items in learning/known — pages reinforce what practice introduced
/// (D-R1); mastered items leave the snapshot (R3 eviction).
public struct SnapshotBuilder: Sendable {
    public var config: EngineConfig

    public init(config: EngineConfig = .default) {
        self.config = config
    }

    public func build(store: LearnerStore) throws -> Snapshot {
        let language = try store.setting(SettingsKey.activeLanguage) ?? "de"
        let version = try store.snapshotVersion()
        let enabled = (try store.setting(SettingsKey.enabled) ?? "true") == "true"
        let pageContextOptIn = (try store.setting(SettingsKey.pageContextOptIn) ?? "false") == "true"
        let blockedHosts = try store.blockedHosts()

        let progress = try store.allProgress()
        let activeStages: Set<Stage> = [.learning, .known]

        let items = try store.items(language: language)
            .filter { item in
                guard item.replacementPolicy == .ambientSafe else { return false }
                guard let stage = progress[item.id]?.stage else { return false }
                return activeStages.contains(stage)
            }
            .map { item -> SnapshotItem in
                // Size control (R3): hover examples ride along only for
                // freshly introduced items; settled items get slim hovers.
                let includeExample = (progress[item.id]?.srsBox ?? 0) <= 1
                return SnapshotItem(
                    id: item.id,
                    kind: item.kind,
                    tier: item.fidelityTier,
                    forms: item.sourceForms.map {
                        SnapshotForm(match: $0.form.lowercased(), display: $0.target)
                    },
                    hover: HoverContent(
                        target: displayTarget(item),
                        pos: item.targetMeta?.pos,
                        example: includeExample ? item.examples.first : nil,
                        seenCount: progress[item.id]?.seenCount ?? 0
                    )
                )
            }

        return Snapshot(
            version: version,
            language: language,
            settings: SnapshotSettings(
                enabled: enabled,
                blockedHosts: blockedHosts,
                pageContextOptIn: pageContextOptIn
            ),
            items: items
        )
    }

    /// Encoded size must stay under the R3 bound; test-enforced.
    public func encodedSize(_ snapshot: Snapshot) throws -> Int {
        try JSONCoding.encoder.encode(snapshot).count
    }

    func displayTarget(_ item: VocabItem) -> String {
        if let gender = item.targetMeta?.gender, !gender.isEmpty {
            return "\(gender) \(item.target)"
        }
        return item.target
    }
}
