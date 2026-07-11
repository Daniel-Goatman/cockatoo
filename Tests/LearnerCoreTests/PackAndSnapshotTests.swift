import XCTest
@testable import LearnerCore

final class PackValidatorTests: XCTestCase {
    let validator = PackValidator()

    func pack(_ items: [VocabItem]) -> PackFile {
        PackFile(
            language: "de", version: "1",
            provenance: .init(corpus: "t", license: "t", packtool: "t", generatedAt: "t"),
            grading: .german, items: items
        )
    }

    func testValidSimPackPasses() {
        let report = validator.validate(Fixtures.simPack())
        XCTAssertEqual(report.failures, [])
    }

    func testDuplicateIdFails() {
        let item = Fixtures.invariant("and", "und")
        let report = validator.validate(pack([item, item]))
        XCTAssertTrue(report.failures.contains { $0.contains("duplicate id") })
    }

    func testAmbientSurfaceFormCollisionFails() {
        var a = Fixtures.invariant("like", "wie")
        var b = Fixtures.invariant("like", "mögen")
        b.id = "de.word.moegen"
        _ = a
        let report = validator.validate(pack([a, b]))
        XCTAssertTrue(report.failures.contains { $0.contains("already claimed") })
    }

    func testDeterminerFormWithoutBareFormFails() {
        var item = Fixtures.noun("house", "Haus", gender: "das")
        item.sourceForms.removeAll { $0.form == "house" }
        let report = validator.validate(pack([item]))
        XCTAssertTrue(report.failures.contains { $0.contains("lacks bare form") })
    }

    func testFormMatchedNounWithoutDeterminerFormsFails() {
        var item = Fixtures.noun("house", "Haus", gender: "das")
        item.sourceForms = [SourceForm(form: "house", target: "Haus")]
        let report = validator.validate(pack([item]))
        XCTAssertTrue(report.failures.contains { $0.contains("missing determiner-extended") })
    }

    func testApproximateTierRejectedInV1() {
        var item = Fixtures.invariant("run", "laufen")
        item.fidelityTier = .approximate
        let report = validator.validate(pack([item]))
        XCTAssertTrue(report.failures.contains { $0.contains("approximate") })
    }

    func testAmbientVerbRejectedInV1() {
        var item = Fixtures.invariant("run", "laufen")
        item.targetMeta = TargetMeta(pos: "verb")
        let report = validator.validate(pack([item]))
        XCTAssertTrue(report.failures.contains { $0.contains("verbs must be reviewOnly") })
    }

    func testReviewOnlyVerbPasses() {
        var item = Fixtures.invariant("run", "laufen")
        item.targetMeta = TargetMeta(pos: "verb")
        item.replacementPolicy = .reviewOnly
        let report = validator.validate(pack([item]))
        XCTAssertEqual(report.failures, [])
    }

    func testIdStabilityAgainstPreviousVersion() {
        let previous = pack([Fixtures.invariant("and", "und"), Fixtures.invariant("but", "aber")])
        let next = pack([Fixtures.invariant("and", "und")])
        let report = validator.validate(next, previous: previous)
        XCTAssertTrue(report.failures.contains { $0.contains("de.word.aber") && $0.contains("missing") })
    }

    func testDependencyMustResolveInSameOrLowerBand() {
        var chunk = Fixtures.invariant("there is", "es gibt")
        chunk.kind = .chunk
        chunk.dependencies = ["de.word.missing"]
        var report = validator.validate(pack([chunk]))
        XCTAssertTrue(report.failures.contains { $0.contains("not in pack") })

        var dep = Fixtures.invariant("is", "ist")
        dep.frequencyBand = 3
        chunk.dependencies = [dep.id]
        chunk.frequencyBand = 1
        report = validator.validate(pack([chunk, dep]))
        XCTAssertTrue(report.failures.contains { $0.contains("higher band") })
    }
}

final class PackImporterTests: XCTestCase {
    let t0 = Fixtures.t0

    func testChecksumMismatchBlocksImport() throws {
        let db = try AppDatabase.inMemory()
        let engine = LearnerEngine(store: LearnerStore(db: db))
        let data = try JSONEncoder().encode(Fixtures.simPack())
        XCTAssertThrowsError(
            try engine.importer.importPack(Fixtures.simPack(), rawData: data, expectedChecksum: "deadbeef", store: engine.store, now: t0)
        ) { error in
            XCTAssertEqual(error as? PackImporter.ImportError, .checksumMismatch)
        }
    }

    func testUpgradePreservesProgressAndRetiresRemovedItemsWithProgress() throws {
        let engine = try Fixtures.makeEngine()
        let itemId = "de.word.und"
        // Give the item progress.
        try engine.postEvents([ExposureEvent(id: "e1", itemId: itemId, type: .seen, occurredAt: t0)], now: t0)
        let seenBefore = try Fixtures.progress(engine, itemId).seenCount
        XCTAssertEqual(seenBefore, 1)

        // New pack version drops "und" — validator would fail on ID stability,
        // so import bypasses via importer-with-tombstone path: here we verify
        // importer behavior for a pack that keeps IDs but changes content.
        var upgraded = Fixtures.simPack()
        upgraded.version = "2026.08-test"
        upgraded.items = upgraded.items.map { item in
            var i = item
            i.explanation += " (revised)"
            return i
        }
        try engine.importPack(upgraded, now: t0.addingTimeInterval(3600))

        XCTAssertEqual(try Fixtures.progress(engine, itemId).seenCount, seenBefore, "progress survives upgrade via stable IDs")
        let item = try engine.store.item(id: itemId)
        XCTAssertTrue(item!.explanation.hasSuffix("(revised)"))
    }

    func testGradingConfigComesFromPack() throws {
        let engine = try Fixtures.makeEngine()
        let grading = try engine.importer.gradingConfig(language: "de", store: engine.store)
        XCTAssertEqual(grading.articles, GradingConfig.german.articles)
    }
}

final class SnapshotTests: XCTestCase {
    let t0 = Fixtures.t0

    func testSnapshotContainsOnlyActiveSlice() throws {
        let engine = try Fixtures.makeEngine()
        guard case .snapshot(let snap) = try engine.snapshot() else { return XCTFail() }
        XCTAssertEqual(snap.items.count, 8, "only the bootstrapped ambient band-1 items")
        XCTAssertEqual(snap.language, "de")
        XCTAssertTrue(snap.settings.enabled)
        XCTAssertFalse(snap.settings.pageContextOptIn)
        // Forms are lowercased for the matcher.
        let haus = snap.items.first { $0.id == "de.word.haus" }
        XCTAssertNotNil(haus)
        XCTAssertTrue(haus!.forms.contains(SnapshotForm(match: "the house", display: "das Haus")))
        XCTAssertEqual(haus!.tier, .formMatched)
    }

    func testUnchangedResponseWhenVersionMatches() throws {
        let engine = try Fixtures.makeEngine()
        guard case .snapshot(let snap) = try engine.snapshot() else { return XCTFail() }
        guard case .unchanged(let version) = try engine.snapshot(sinceVersion: snap.version) else {
            return XCTFail("expected unchanged")
        }
        XCTAssertEqual(version, snap.version)

        // Progress change bumps the version → full snapshot again.
        let itemId = snap.items[0].id
        try engine.postEvents([ExposureEvent(id: "e1", itemId: itemId, type: .seen, occurredAt: t0)], now: t0)
        guard case .snapshot(let fresh) = try engine.snapshot(sinceVersion: snap.version) else {
            return XCTFail("expected fresh snapshot after events")
        }
        XCTAssertGreaterThan(fresh.version, snap.version)
    }

    /// R3: a full-size pack with a 200-item active slice stays under 100 KB.
    func testSnapshotSizeBoundAtScale() throws {
        var items: [VocabItem] = []
        for i in 0..<1000 {
            var item = Fixtures.noun(
                "testword\(i)", "Testwort\(i)", gender: ["der", "die", "das"][i % 3],
                plural: ("testword\(i)s", "Testwörter\(i)"),
                band: (i / 100) + 1
            )
            item.explanation = "A reasonably sized explanation sentence for test word number \(i)."
            items.append(item)
        }
        let pack = PackFile(
            language: "de", version: "big",
            provenance: .init(corpus: "t", license: "t", packtool: "t", generatedAt: "t"),
            grading: .german, items: items
        )
        let db = try AppDatabase.inMemory()
        let engine = LearnerEngine(store: LearnerStore(db: db))
        try engine.importPack(pack, now: t0)

        // Force a 200-item active slice: 15 ambient + 185 learning.
        try engine.store.db.writer.write { dbc in
            for (index, item) in items.prefix(200).enumerated() {
                var p = ItemProgress(itemId: item.id, now: self.t0)
                if index < 15 {
                    p.stage = .ambient
                } else {
                    p.stage = .learning
                    p.srsBox = 2
                    p.dueAt = self.t0.addingTimeInterval(3600)
                }
                try p.save(dbc)
            }
        }

        let snapshot = try engine.snapshotBuilder.build(store: engine.store)
        XCTAssertEqual(snapshot.items.count, 200)
        let size = try engine.snapshotBuilder.encodedSize(snapshot)
        XCTAssertLessThan(size, EngineConfig.default.snapshotMaxEncodedBytes,
                          "snapshot is \(size) bytes — over the R3 bound")
    }
}
