import Foundation
import LearnerCore

// learnerctl — debug CLI over a Cockatoo database.
//
//   learnerctl --db <path> import <pack.json>
//   learnerctl --db <path> overview
//   learnerctl --db <path> snapshot
//   learnerctl --db <path> simulate --days 30 [--seed N] [--persist]
//   learnerctl --db <path> session
//
// simulate runs in an in-memory SANDBOX seeded from the database's pack:
// nothing is saved unless --persist is passed (which runs against the real
// database, e.g. to seed dev state for the app).

let args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func option(_ name: String) -> String? {
    guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
    return args[index + 1]
}

let positional = args.enumerated().filter { index, arg in
    !arg.hasPrefix("--") && (index == 0 || !args[index - 1].hasPrefix("--"))
}.map(\.element)

guard let command = positional.first else {
    print("usage: learnerctl [--db <path>] <import|overview|snapshot|simulate|session> ...")
    exit(0)
}

let engine: LearnerEngine
do {
    let db: AppDatabase
    if let path = option("--db") {
        db = try AppDatabase.onDisk(at: URL(fileURLWithPath: path))
    } else {
        db = try AppDatabase.onDisk(at: CockatooPaths.databaseURL())
    }
    engine = LearnerEngine(store: LearnerStore(db: db))
} catch {
    fail("cannot open database: \(error)")
}

let now = Date()

switch command {
case "import":
    guard positional.count >= 2 else { fail("usage: learnerctl import <pack.json>") }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: positional[1]))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pack = try decoder.decode(PackFile.self, from: data)
        let count = try engine.importPack(pack, rawData: data, now: now)
        print("imported \(count) items from \(pack.language)-\(pack.version)")
    } catch {
        fail("\(error)")
    }

case "overview":
    do {
        let o = try engine.overview(now: now)
        print("library: \(o.libraryCount)/\(o.totalItems)   due now: \(o.dueNow)   new today: \(o.newToday)/\(o.newPerDay)")
        for stage in Stage.allCases {
            let label = stage.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            print("  \(label)\(o.countsByStage[stage] ?? 0)")
        }
        if let m = o.nextMilestone {
            print("next milestone: band \(m.band) — \(m.known)/\(m.needed) known (of \(m.total))")
        }
    } catch {
        fail("\(error)")
    }

case "snapshot":
    do {
        guard case .snapshot(let snap) = try engine.snapshot() else { fail("unexpected") }
        let size = try engine.snapshotBuilder.encodedSize(snap)
        print("version \(snap.version): \(snap.items.count) active items, \(size) bytes")
        for item in snap.items {
            print("  \(item.id) [\(item.tier.rawValue)] \(item.forms.map(\.match).joined(separator: " | "))")
        }
    } catch {
        fail("\(error)")
    }

case "simulate":
    let days = Int(option("--days") ?? "30") ?? 30
    let seed = UInt64(option("--seed") ?? "1") ?? 1
    let persist = args.contains("--persist")
    do {
        // Sandbox by default: copy the pack into an in-memory engine so
        // repeated runs never contaminate real learning state.
        let language = try engine.store.setting(SettingsKey.activeLanguage) ?? "und"
        guard try !engine.store.items(language: language).isEmpty else {
            fail("no pack in this database — run 'learnerctl import <pack.json>' against the same --db first")
        }
        let sim: LearnerEngine
        if persist {
            sim = engine
        } else {
            let items = try engine.store.items(language: language)
            let pack = PackFile(
                language: language,
                version: "sandbox",
                provenance: .init(corpus: "sandbox copy", license: "-", packtool: "-", generatedAt: "-"),
                grading: try engine.importer.gradingConfig(language: language, store: engine.store),
                items: items
            )
            sim = LearnerEngine(store: LearnerStore(db: try AppDatabase.inMemory()))
            try sim.importPack(pack, now: now)
        }

        var rng = SplitMix64(seed: seed)
        var clock = now
        var counter = 0
        var totalAnswered = 0
        var totalCorrect = 0
        var firstMasteredReported = false
        var celebratedBands = Set<Int>()
        let itemName: (String) throws -> String = { id in
            guard let item = try sim.store.item(id: id) else { return id }
            let english = item.sourceForms.first { !$0.form.contains(" ") }?.form ?? item.sourceForms[0].form
            return "\(item.target) (\(english))"
        }

        print("Simulating \(days) days of browsing + practice at 85% accuracy (seed \(seed))\(persist ? " — PERSISTING to database" : " — sandbox, nothing will be saved")")
        print("")
        print("day   library  learning  known  mastered  new   answered")
        print("────  ───────  ────────  ─────  ────────  ───   ────────")

        for day in 0..<days {
            var answeredToday = 0
            for bout in 0..<4 {
                clock = clock.addingTimeInterval(4 * 3600)
                // Browsing: library words get sighted on pages (display-only).
                var events: [ExposureEvent] = []
                for p in try sim.store.allProgress().values where p.stage < .mastered {
                    guard rng.next() % 100 < 30 else { continue }
                    counter += 1
                    events.append(ExposureEvent(id: "ctl-\(counter)", itemId: p.itemId, type: .seen, occurredAt: clock))
                    if rng.next() % 100 < 20, let item = try sim.store.item(id: p.itemId) {
                        counter += 1
                        events.append(ExposureEvent(
                            id: "ctl-\(counter)", itemId: p.itemId, type: .sentenceCaptured, occurredAt: clock,
                            sentence: "Yesterday we talked about the \(item.sourceForms.last!.form) for a while."
                        ))
                    }
                }
                try sim.postEvents(events, now: clock)
                if bout % 2 == 0 {
                    let session = try sim.planSession(now: clock, seed: rng.next())
                    for planned in session.queue {
                        let correct = rng.next() % 100 < 85
                        _ = try sim.grade(result: .init(
                            itemId: planned.question.itemId,
                            mode: planned.question.mode,
                            correct: correct, answeredAt: clock
                        ), now: clock)
                        answeredToday += 1
                        totalAnswered += 1
                        if correct { totalCorrect += 1 }
                    }
                    if let band = try sim.pendingMilestone(now: clock), !celebratedBands.contains(band) {
                        celebratedBands.insert(band)
                        try sim.markMilestoneCelebrated(band: band, now: clock)
                        print("      ▸ band \(band) milestone — \(Int(EngineConfig.default.milestoneFraction * 100))% known")
                    }
                }
            }

            let o = try sim.overview(now: clock)
            func col(_ stage: Stage) -> String { String(o.countsByStage[stage] ?? 0).leftPadded(to: 5) }
            print("\(String(day + 1).leftPadded(to: 4))  \(String(o.libraryCount).leftPadded(to: 7))  \(col(.learning).leftPadded(to: 8))  \(col(.known))  \(col(.mastered).leftPadded(to: 8))  \(String(o.newToday).leftPadded(to: 3))   \(String(answeredToday).leftPadded(to: 8))")

            if !firstMasteredReported, (o.countsByStage[.mastered] ?? 0) > 0 {
                let mastered = try sim.store.allProgress().values.first { $0.stage == .mastered }
                if let mastered {
                    print("      ▸ first word mastered: \(try itemName(mastered.itemId))")
                }
                firstMasteredReported = true
            }
        }

        // Final report.
        let o = try sim.overview(now: clock)
        let accuracy = totalAnswered > 0 ? Int((Double(totalCorrect) / Double(totalAnswered) * 100).rounded()) : 0
        print("")
        print("── after \(days) simulated days ──")
        print("questions answered: \(totalAnswered) (\(accuracy)% correct)   library: \(o.libraryCount)/\(o.totalItems)")
        let maxCount = max(1, Stage.allCases.map { o.countsByStage[$0] ?? 0 }.max() ?? 1)
        for stage in Stage.allCases {
            let count = o.countsByStage[stage] ?? 0
            let bar = String(repeating: "█", count: Int((Double(count) / Double(maxCount) * 24).rounded()))
            print("  \(stage.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(String(count).leftPadded(to: 3))  \(bar)")
        }
        let knownIds = try sim.store.allProgress().values
            .filter { $0.stage >= .known }
            .sorted { $0.itemId < $1.itemId }
            .prefix(8)
            .map(\.itemId)
        if !knownIds.isEmpty {
            print("  now knows: \(try knownIds.map(itemName).joined(separator: ", "))\((o.countsByStage[.known] ?? 0) + (o.countsByStage[.mastered] ?? 0) > 8 ? ", …" : "")")
        }
        if !persist {
            print("")
            print("(sandbox run — nothing was saved; pass --persist to write into the database)")
        }
    } catch {
        fail("\(error)")
    }

case "session":
    do {
        let session = try engine.planSession(now: now, seed: UInt64(now.timeIntervalSince1970))
        if session.queue.isEmpty {
            print("nothing due")
        }
        for (i, planned) in session.queue.enumerated() {
            switch planned.question {
            case .recognition(let id, let prompt, let options, let correct):
                print("\(i + 1). [recognition] \(id): \(prompt) → \(options.joined(separator: " / ")) (answer: \(options[correct]))")
            case .recall(let id, let prompt, let expected):
                print("\(i + 1). [recall] \(id): \(prompt) → \(expected)")
            case .cloze(let id, let sentence, let hint, let expected):
                print("\(i + 1). [cloze] \(id): \(sentence)\(hint.map { " (\($0))" } ?? "") → \(expected)")
            case .rebuild(let id, let source, _, let order):
                print("\(i + 1). [rebuild] \(id): \(source) → \(order.joined(separator: " "))")
            case .selfGrade(let id, let prompt, _, _):
                print("\(i + 1). [selfGrade] \(id): \(prompt)")
            }
        }
    } catch {
        fail("\(error)")
    }

default:
    fail("unknown command '\(command)'")
}

extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
