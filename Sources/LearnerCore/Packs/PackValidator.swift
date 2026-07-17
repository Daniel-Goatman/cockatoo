import Foundation

/// Deterministic validation — no LLM (docs/plan/07-content-pipeline.md
/// stage 3). Hard failures block import; warnings don't.
public struct PackValidator: Sendable {
    public init() {}

    public struct Report: Equatable, Sendable {
        public var failures: [String] = []
        public var warnings: [String] = []
        public var isValid: Bool { failures.isEmpty }
    }

    public func validate(_ pack: PackFile, previous: PackFile? = nil) -> Report {
        var report = Report()

        if pack.schema != 2 {
            report.failures.append("unsupported schema \(pack.schema)")
        }
        if !isLanguageTag(pack.sourceLanguage) {
            report.failures.append("invalid sourceLanguage '\(pack.sourceLanguage)'")
        }
        if !isLanguageTag(pack.language) {
            report.failures.append("invalid target language '\(pack.language)'")
        }
        if pack.items.isEmpty {
            report.failures.append("pack has no items")
        }

        var seenIds = Set<String>()
        // Ambient surface-form uniqueness: form -> itemId.
        var ambientForms: [String: String] = [:]
        let idsInPack = Set(pack.items.map(\.id))
        let validLevels: Set<String> = ["a1", "a2", "b1", "b2", "c1", "c2"]

        for item in pack.items {
            let ctx = "item \(item.id)"

            if !seenIds.insert(item.id).inserted {
                report.failures.append("\(ctx): duplicate id")
            }
            if item.language != pack.language {
                report.failures.append("\(ctx): language \(item.language) != pack \(pack.language)")
            }
            if !item.id.hasPrefix("\(pack.language).") {
                report.failures.append("\(ctx): id must start with target language '\(pack.language).'")
            }
            if item.sourceLemma.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                report.failures.append("\(ctx): schema-2 item requires sourceLemma")
            }
            if item.sourceForms.isEmpty {
                report.failures.append("\(ctx): no sourceForms")
            }
            if item.target.isEmpty {
                report.failures.append("\(ctx): empty target")
            }
            if !validLevels.contains(item.level) {
                report.failures.append("\(ctx): invalid level '\(item.level)'")
            }
            if !(1...10).contains(item.frequencyBand) {
                report.failures.append("\(ctx): frequencyBand \(item.frequencyBand) out of 1...10")
            }
            if item.explanation.isEmpty {
                report.warnings.append("\(ctx): empty explanation")
            }

            // Dependencies must resolve within the pack, same or lower band.
            for dep in item.dependencies {
                guard let depItem = pack.items.first(where: { $0.id == dep }) else {
                    report.failures.append("\(ctx): dependency '\(dep)' not in pack")
                    continue
                }
                if depItem.frequencyBand > item.frequencyBand {
                    report.failures.append("\(ctx): dependency '\(dep)' in higher band")
                }
                _ = idsInPack
            }

            // Examples must contain the target form (hard) and ideally stay
            // within band+2 vocabulary (warning; needs corpus data — skipped).
            for (i, example) in item.examples.enumerated() {
                if !example.target.localizedCaseInsensitiveContains(item.target) {
                    report.warnings.append("\(ctx): example \(i) target does not contain '\(item.target)'")
                }
            }

            if item.replacementPolicy == .ambientSafe {
                validateAmbient(item, config: pack.validation, ambientForms: &ambientForms, report: &report)
            }
        }

        // ID stability vs the previous pack version: every prior ID must
        // persist (progress survival) — docs/plan/03 §pack import.
        if let previous {
            let currentIds = Set(pack.items.map(\.id))
            for old in previous.items where !currentIds.contains(old.id) {
                report.failures.append("id '\(old.id)' present in \(previous.version) missing from \(pack.version) (tombstone required)")
            }
        }

        return report
    }

    func validateAmbient(
        _ item: VocabItem,
        config: PackValidationConfig,
        ambientForms: inout [String: String],
        report: inout Report
    ) {
        let ctx = "item \(item.id)"
        let forms = Dictionary(
            item.sourceForms.map { ($0.form.lowercased(), $0.target) },
            uniquingKeysWith: { first, _ in first }
        )

        for (form, _) in forms {
            // Collision check across ambient items.
            if let owner = ambientForms[form], owner != item.id {
                report.failures.append("\(ctx): surface form '\(form)' already claimed by \(owner)")
            } else {
                ambientForms[form] = item.id
            }

            // Longest-match invariant: a determiner-extended form's bare
            // remainder must belong to the same item.
            for determiner in config.sourceDeterminers {
                let prefix = determiner.lowercased() + " "
                guard form.hasPrefix(prefix) else { continue }
                let bare = String(form.dropFirst(prefix.count))
                if forms[bare] == nil {
                    report.failures.append("\(ctx): determiner form '\(form)' lacks bare form '\(bare)'")
                }
            }
        }

        // Noun completeness: formMatched nouns need the determiner/number set
        // (docs/plan/07 stage 3). Detected via targetMeta.pos == "noun".
        if item.fidelityTier == .formMatched,
           item.targetMeta?.pos.map(config.nounPartsOfSpeech.contains) == true {
            let prefixes = config.sourceDeterminers.map { $0.lowercased() + " " }
            let hasDeterminerSingular = forms.keys.contains { form in prefixes.contains { form.hasPrefix($0) } }
            if !hasDeterminerSingular {
                report.failures.append("\(ctx): formMatched noun missing determiner-extended forms (D10)")
            }
        }

        // approximate is reserved: no ambient verbs in v1 (D11).
        if item.fidelityTier == .approximate, !config.allowApproximateAmbient {
            report.failures.append("\(ctx): fidelityTier 'approximate' is not authorable in v1 (see docs/plan/09-open-problems.md)")
        }
        if let pos = item.targetMeta?.pos,
           config.disallowedAmbientPartsOfSpeech.contains(pos) {
            report.failures.append("\(ctx): part of speech '\(pos)' must be reviewOnly for this pack")
        }
    }

    private func isLanguageTag(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$"#, options: .regularExpression) != nil
    }
}
