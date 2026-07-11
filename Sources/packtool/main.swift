import Foundation
import LearnerCore

// packtool — content pipeline CLI (docs/plan/07-content-pipeline.md).
//
//   packtool validate <pack.json> [--previous <prev.json>]
//   packtool checksum <pack.json>
//   packtool review <new.json> --previous <prev.json>
//   packtool import-test <pack.json>

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

    The LLM authoring pass (stage 2: candidates → authored items) requires a
    configured OpenAI-compatible provider; see docs/plan/07-content-pipeline.md.
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
        print("imported \(count) items; ambient bootstrap: \(overview.countsByStage[.ambient] ?? 0); snapshot \(snap.items.count) items, \(size) bytes")
    } catch {
        fail("import failed: \(error)")
    }

case "author":
    fail("the LLM authoring pass needs a configured provider (base URL + key + model) — see docs/plan/07-content-pipeline.md stage 2")

default:
    fail("unknown command '\(command)'")
}
