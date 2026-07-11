import Foundation
import LearnerCore

// learnerctl — debug CLI over a Cockatoo database.
//
//   learnerctl --db <path> import <pack.json>
//   learnerctl --db <path> overview
//   learnerctl --db <path> snapshot
//   learnerctl --db <path> simulate --days 30
//   learnerctl --db <path> session

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
        print("unlocked tier: \(o.unlockedTier)   items: \(o.totalItems)   due now: \(o.dueNow)")
        for stage in Stage.allCases {
            let label = stage.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            print("  \(label)\(o.countsByStage[stage] ?? 0)")
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
    do {
        let grading = try engine.importer.gradingConfig(language: "de", store: engine.store)
        _ = grading
        var rng = SplitMix64(seed: 1)
        var clock = now
        var counter = 0
        for day in 0..<days {
            for bout in 0..<4 {
                clock = clock.addingTimeInterval(4 * 3600)
                var events: [ExposureEvent] = []
                for p in try engine.store.allProgress().values where p.stage == .ambient || p.stage == .ready {
                    counter += 1
                    events.append(ExposureEvent(id: "ctl-\(counter)", itemId: p.itemId, type: .seen, occurredAt: clock))
                    if rng.next() % 100 < 40 {
                        counter += 1
                        events.append(ExposureEvent(id: "ctl-\(counter)", itemId: p.itemId, type: .engaged, occurredAt: clock))
                    }
                }
                try engine.postEvents(events, now: clock)
                if bout % 2 == 0 {
                    let session = try engine.planSession(now: clock, seed: rng.next())
                    for planned in session.queue {
                        let correct = rng.next() % 100 < 85
                        _ = try engine.grade(result: .init(
                            itemId: planned.question.itemId,
                            mode: planned.question.mode,
                            correct: correct, answeredAt: clock
                        ), now: clock)
                    }
                }
            }
            let o = try engine.overview(now: clock)
            print("day \(day + 1): tier \(o.unlockedTier), known+ \( (o.countsByStage[.known] ?? 0) + (o.countsByStage[.mastered] ?? 0) )")
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
            case .cloze(let id, let sentence, let expected):
                print("\(i + 1). [cloze] \(id): \(sentence) → \(expected)")
            }
        }
    } catch {
        fail("\(error)")
    }

default:
    fail("unknown command '\(command)'")
}
