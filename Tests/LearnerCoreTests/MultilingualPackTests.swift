import XCTest
@testable import LearnerCore

final class MultilingualPackTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadSpanishSource() throws -> (PackFile, Data) {
        let url = repoRoot.appendingPathComponent("packs/sources/es/sample.accepted.json")
        let data = try Data(contentsOf: url)
        return (try JSONCoding.decoder.decode(PackFile.self, from: data), data)
    }

    func testSpanishFixtureValidatesImportsAndProducesPractice() throws {
        let (pack, data) = try loadSpanishSource()
        XCTAssertEqual(pack.sourceLanguage, "en")
        XCTAssertEqual(pack.language, "es")
        XCTAssertEqual(PackValidator().validate(pack).failures, [])

        let engine = LearnerEngine(store: LearnerStore(db: try AppDatabase.inMemory()))
        XCTAssertEqual(try engine.importPack(pack, rawData: data, now: Fixtures.t0), 6)
        XCTAssertEqual(try engine.store.setting(SettingsKey.activeLanguage), "es")

        let session = try engine.planSession(now: Fixtures.t0, seed: 7)
        XCTAssertFalse(session.queue.isEmpty)
        XCTAssertTrue(session.queue.allSatisfy { $0.question.itemId.hasPrefix("es.") })
        XCTAssertEqual(session.grading.localeIdentifier, "es")
    }

    func testSpanishGradingUsesPackRules() {
        let grading = GradingConfig(
            articles: ["el", "la", "los", "las", "un", "una"],
            localeIdentifier: "es",
            diacriticInsensitive: false
        )
        let grader = Grader(grading: grading)
        XCTAssertEqual(
            grader.checkTyped(question: .recall(itemId: "es.word.casa", prompt: "house", expected: "la casa"), answer: "casa"),
            .correct
        )
        XCTAssertEqual(
            grader.checkTyped(question: .recall(itemId: "es.word.tambien", prompt: "also", expected: "también"), answer: "tambien"),
            .nearMiss(expected: "también")
        )
    }

    func testValidatorUsesPackProvidedSourceDeterminers() {
        let item = VocabItem(
            id: "es.word.casa",
            language: "es",
            sourceLemma: "maison",
            kind: .word,
            sourceForms: [
                SourceForm(form: "la maison", target: "la casa"),
                SourceForm(form: "une maison", target: "una casa"),
                SourceForm(form: "maison", target: "casa"),
            ],
            target: "casa",
            targetMeta: TargetMeta(gender: "la", pos: "noun"),
            level: "a1",
            frequencyBand: 1,
            replacementPolicy: .ambientSafe,
            fidelityTier: .formMatched,
            explanation: "la casa means maison.",
            examples: [Example(source: "La maison est petite.", target: "La casa es pequeña.")]
        )
        let pack = PackFile(
            sourceLanguage: "fr",
            language: "es",
            version: "test",
            provenance: .init(corpus: "test", license: "test", packtool: "test", generatedAt: "test"),
            grading: GradingConfig(articles: ["el", "la"], localeIdentifier: "es"),
            validation: PackValidationConfig(sourceDeterminers: ["le", "la", "un", "une"]),
            items: [item]
        )

        XCTAssertEqual(PackValidator().validate(pack).failures, [])
    }

    func testAcceptedSourceMatchesReviewAndCanonicalBuild() throws {
        let (pack, sourceData) = try loadSpanishSource()
        let reviewURL = repoRoot.appendingPathComponent("packs/sources/es/sample.review.json")
        let review = try JSONCoding.decoder.decode(PackReviewRecord.self, from: Data(contentsOf: reviewURL))
        XCTAssertEqual(review.validate(for: pack, sourceData: sourceData), [])

        let built = try Data(contentsOf: repoRoot.appendingPathComponent("packs/build/es-sample-2026.01.json"))
        XCTAssertEqual(built, try pack.canonicalData())
    }

    func testInstalledLanguagesCanBeSwitchedWithoutChangingProgress() throws {
        let database = try AppDatabase.inMemory()
        let engine = LearnerEngine(store: LearnerStore(db: database))
        let german = Fixtures.simPack()
        let germanData = try JSONCoding.encoder.encode(german)
        let (spanish, spanishData) = try loadSpanishSource()

        try engine.importPack(german, rawData: germanData, now: Fixtures.t0)
        try Fixtures.seed(engine, german.items[0].id) { progress in
            progress.seenCount = 9
        }
        let versionBeforeSwitch = try engine.store.snapshotVersion()

        // Installing another pack is non-switching at the engine boundary;
        // the app switches only when an explicit import or picker action asks.
        try engine.importPack(
            spanish,
            rawData: spanishData,
            now: Fixtures.t0.addingTimeInterval(60)
        )
        XCTAssertEqual(try engine.store.setting(SettingsKey.activeLanguage), "de")
        XCTAssertEqual(try engine.store.installedLanguages(), ["es", "de"])

        try engine.store.activateLanguage("es")
        XCTAssertEqual(try engine.store.setting(SettingsKey.activeLanguage), "es")
        XCTAssertGreaterThan(try engine.store.snapshotVersion(), versionBeforeSwitch)
        guard case .snapshot(let snapshot) = try engine.snapshot() else {
            return XCTFail("Expected a fresh snapshot after switching languages")
        }
        XCTAssertEqual(snapshot.language, "es")
        XCTAssertTrue(try engine.planSession(now: Fixtures.t0, seed: 12).queue.allSatisfy {
            $0.question.itemId.hasPrefix("es.")
        })

        try engine.store.activateLanguage("de")
        XCTAssertEqual(try engine.store.progress(itemId: german.items[0].id)?.seenCount, 9)
        XCTAssertThrowsError(try engine.store.activateLanguage("fr")) { error in
            XCTAssertEqual(
                error as? LearnerStore.LanguageActivationError,
                .languageNotInstalled("fr")
            )
        }
    }
}
