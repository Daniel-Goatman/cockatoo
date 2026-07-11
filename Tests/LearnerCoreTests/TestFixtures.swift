import Foundation
@testable import LearnerCore

enum Fixtures {
    static let t0 = ISO8601DateFormatter().date(from: "2026-07-01T08:00:00Z")!

    static func noun(
        _ english: String,
        _ german: String,
        gender: String,
        plural: (String, String)? = nil, // (english, german)
        band: Int = 1,
        indefinite: String = "ein"
    ) -> VocabItem {
        var forms = [
            SourceForm(form: "the \(english)", target: "\(gender) \(german)"),
            SourceForm(form: "a \(english)", target: "\(indefinite) \(german)"),
            SourceForm(form: english, target: german),
        ]
        if let plural {
            forms.append(SourceForm(form: plural.0, target: plural.1))
            forms.append(SourceForm(form: "the \(plural.0)", target: "die \(plural.1)"))
        }
        return VocabItem(
            id: "de.word.\(german.lowercased())",
            language: "de",
            kind: .word,
            sourceForms: forms,
            target: german,
            targetMeta: TargetMeta(gender: gender, plural: plural?.1, pos: "noun"),
            level: "a1",
            frequencyBand: band,
            replacementPolicy: .ambientSafe,
            fidelityTier: .formMatched,
            explanation: "\(german) means \(english).",
            examples: [Example(source: "I see the \(english).", target: "Ich sehe \(gender == "das" ? "das" : "den") \(german).")]
        )
    }

    static func invariant(_ english: String, _ german: String, band: Int = 1) -> VocabItem {
        VocabItem(
            id: "de.word.\(german.lowercased())",
            language: "de",
            kind: .word,
            sourceForms: [SourceForm(form: english, target: german)],
            target: german,
            targetMeta: TargetMeta(pos: "conjunction"),
            level: "a1",
            frequencyBand: band,
            replacementPolicy: .ambientSafe,
            fidelityTier: .exact,
            explanation: "\(german) means \(english).",
            examples: [Example(source: "Bread \(english) butter.", target: "Brot \(german) Butter.")]
        )
    }

    /// 24 items across bands 1-3 (8 per band): 4 nouns + 4 invariants each.
    static func simPack() -> PackFile {
        var items: [VocabItem] = []
        let nouns: [(String, String, String, (String, String))] = [
            ("house", "Haus", "das", ("houses", "Häuser")),
            ("dog", "Hund", "der", ("dogs", "Hunde")),
            ("city", "Stadt", "die", ("cities", "Städte")),
            ("child", "Kind", "das", ("children", "Kinder")),
            ("water", "Wasser", "das", ("waters", "Wasser")),
            ("book", "Buch", "das", ("books", "Bücher")),
            ("friend", "Freund", "der", ("friends", "Freunde")),
            ("night", "Nacht", "die", ("nights", "Nächte")),
            ("world", "Welt", "die", ("worlds", "Welten")),
            ("hand", "Hand", "die", ("hands", "Hände")),
            ("year", "Jahr", "das", ("years", "Jahre")),
            ("door", "Tür", "die", ("doors", "Türen")),
        ]
        let invariants: [(String, String)] = [
            ("and", "und"), ("but", "aber"), ("also", "auch"), ("not", "nicht"),
            ("here", "hier"), ("today", "heute"), ("never", "nie"), ("always", "immer"),
            ("often", "oft"), ("again", "wieder"), ("now", "jetzt"), ("only", "nur"),
        ]
        for band in 1...3 {
            for i in 0..<4 {
                let n = nouns[(band - 1) * 4 + i]
                items.append(noun(n.0, n.1, gender: n.2, plural: n.3, band: band, indefinite: n.2 == "die" ? "eine" : "ein"))
                let inv = invariants[(band - 1) * 4 + i]
                items.append(invariant(inv.0, inv.1, band: band))
            }
        }
        return PackFile(
            language: "de",
            version: "2026.07-test",
            provenance: .init(corpus: "test", license: "test", packtool: "test", generatedAt: "2026-07-01"),
            grading: .german,
            items: items
        )
    }

    static func makeEngine(pack: PackFile = simPack(), config: EngineConfig = .default) throws -> LearnerEngine {
        let db = try AppDatabase.inMemory()
        let engine = LearnerEngine(store: LearnerStore(db: db), config: config)
        try engine.importPack(pack, now: t0)
        return engine
    }

    static func progress(_ engine: LearnerEngine, _ itemId: String) throws -> ItemProgress {
        try engine.store.progress(itemId: itemId)!
    }
}
