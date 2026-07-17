import Foundation
import LearnerCore

// packtool — content pipeline CLI (docs/plan/07-content-pipeline.md).
//
//   packtool validate <pack.json> [--previous <prev.json>]
//   packtool checksum <pack.json>
//   packtool review <new.json> --previous <prev.json>
//   packtool import-test <pack.json>
//   packtool build <accepted-source.json> --review <review.json> --output <pack.json>

let args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func loadPack(_ path: String) -> (PackFile, Data) {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else { fail("cannot read \(path)") }
    do {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try decoder.decode(PackFile.self, from: data), data)
    } catch {
        fail("cannot parse \(path): \(error)")
    }
}

func loadReview(_ path: String) -> PackReviewRecord {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else { fail("cannot read \(path)") }
    do {
        return try JSONDecoder().decode(PackReviewRecord.self, from: data)
    } catch {
        fail("cannot parse review \(path): \(error)")
    }
}

func option(_ name: String) -> String? {
    guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
    return args[index + 1]
}

guard let command = args.first else {
    print("""
    packtool — Cockatoo language pack pipeline

    Commands:
      validate <pack.json> [--previous <prev.json>]   deterministic validation (stage 3)
      checksum <pack.json>                            sha256 for distribution
      review <new.json> --previous <prev.json>        human-review markdown diff (stage 4)
      import-test <pack.json>                         import into a scratch DB and report
      build <accepted-source.json> --review <review.json> --output <pack.json>
                                                     review-gated deterministic emission

    Agent/LLM drafting stays outside the runtime. See packs/README.md for the
    provider-neutral draft → review → deterministic build workflow.
    """)
    exit(0)
}

switch command {
case "validate":
    guard args.count >= 2 else { fail("usage: packtool validate <pack.json> [--previous <prev.json>]") }
    let (pack, _) = loadPack(args[1])
    let previous = option("--previous").map { loadPack($0).0 }
    let report = PackValidator().validate(pack, previous: previous)
    for warning in report.warnings { print("warning: \(warning)") }
    for failure in report.failures { print("FAIL: \(failure)") }
    print("\(pack.language)-\(pack.version): \(pack.items.count) items, \(report.failures.count) failures, \(report.warnings.count) warnings")
    exit(report.isValid ? 0 : 1)

case "checksum":
    guard args.count >= 2 else { fail("usage: packtool checksum <pack.json>") }
    let (_, data) = loadPack(args[1])
    print(PackFile.checksum(of: data))

case "build":
    guard args.count >= 2, let reviewPath = option("--review"), let outputPath = option("--output") else {
        fail("usage: packtool build <accepted-source.json> --review <review.json> --output <pack.json>")
    }
    let (pack, sourceData) = loadPack(args[1])
    let report = PackValidator().validate(pack)
    guard report.isValid else {
        for failure in report.failures { FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8)) }
        fail("accepted source failed deterministic validation")
    }
    let review = loadReview(reviewPath)
    let reviewFailures = review.validate(for: pack, sourceData: sourceData)
    guard reviewFailures.isEmpty else {
        for failure in reviewFailures { FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8)) }
        fail("human review gate failed")
    }
    do {
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try pack.canonicalData()
        try data.write(to: outputURL, options: .atomic)
        print("built \(pack.language)-\(pack.version): \(pack.items.count) items, sha256 \(PackFile.checksum(of: data))")
    } catch {
        fail("cannot write \(outputPath): \(error)")
    }

case "review":
    guard args.count >= 2, let previousPath = option("--previous") else {
        fail("usage: packtool review <new.json> --previous <prev.json>")
    }
    let (next, _) = loadPack(args[1])
    let (previous, _) = loadPack(previousPath)
    let prevById = Dictionary(uniqueKeysWithValues: previous.items.map { ($0.id, $0) })
    let nextIds = Set(next.items.map(\.id))

    print("# Pack review: \(previous.version) → \(next.version)\n")
    let added = next.items.filter { prevById[$0.id] == nil }
    print("## Added (\(added.count))\n")
    for item in added {
        print("- **\(item.id)** [band \(item.frequencyBand), \(item.fidelityTier.rawValue)]: \(item.sourceForms.map(\.form).joined(separator: ", ")) → \(item.target)")
    }
    let changed = next.items.filter { item in prevById[item.id].map { $0 != item } ?? false }
    print("\n## Changed (\(changed.count))\n")
    for item in changed { print("- **\(item.id)**") }
    let removed = previous.items.filter { !nextIds.contains($0.id) }
    print("\n## Removed (\(removed.count)) — requires tombstones\n")
    for item in removed { print("- **\(item.id)**") }

case "import-test":
    guard args.count >= 2 else { fail("usage: packtool import-test <pack.json>") }
    let (pack, data) = loadPack(args[1])
    do {
        let db = try AppDatabase.inMemory()
        let engine = LearnerEngine(store: LearnerStore(db: db))
        let count = try engine.importPack(pack, rawData: data, now: Date())
        let overview = try engine.overview(now: Date())
        guard case .snapshot(let snap) = try engine.snapshot() else { fail("no snapshot") }
        let size = try engine.snapshotBuilder.encodedSize(snap)
        print("imported \(count) items; intake candidates: \(overview.introAvailable); snapshot \(snap.items.count) items, \(size) bytes")
    } catch {
        fail("import failed: \(error)")
    }

default:
    fail("unknown command '\(command)'")
}
