import Foundation
import SwiftData

enum UnitSystem: String, CaseIterable {
    case imperial, metric
    var label: String { self == .imperial ? "lb" : "kg" }
    // Weights are stored in kg; converted only for display.
    func display(_ kg: Double) -> Double { self == .imperial ? kg * 2.20462 : kg }
    func toKg(_ value: Double) -> Double { self == .imperial ? value / 2.20462 : value }
}

struct ExerciseTemplate: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var sets: Int
    var reps: String
    // Exercises next to each other with the same superset tag are done as a superset:
    // one set of each in turn, then rest. nil = a normal straight-sets exercise.
    var superset: String? = nil
}

struct WorkoutTemplate: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var exercises: [ExerciseTemplate]
}

@Model
final class SetLog {
    var date: Date
    var exerciseID: String
    var setNumber: Int
    var weightKg: Double
    var reps: Int

    init(date: Date = .now, exerciseID: String, setNumber: Int, weightKg: Double, reps: Int) {
        self.date = date
        self.exerciseID = exerciseID
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
    }
}

// MARK: - Workout focus, worked out from the exercises
// Each exercise counts as lower body, upper body or core. The focus is:
//   mostly one region → "Lower body" / "Upper body" (plus "+ core" if there's any core work),
//   a real mix of upper and lower (the smaller side at least a third) → "Full body",
//   only core → "Core", nothing recognisable → "Mixed".
// The stored title keeps just the name ("Workout A"); older titles like "Workout A · Lower body"
// still work because only the part before " · " is used as the name.

enum BodyRegion { case lower, upper, core, other }

extension ExerciseTemplate {
    var region: BodyRegion {
        switch id {
        case "goblet-squat", "db-rdl", "reverse-lunge", "glute-bridge", "lateral-walk",
             "db-deadlift", "step-up", "hip-thrust":
            return .lower
        case "db-bench", "one-arm-row", "seated-press", "rear-delt-fly", "push-up",
             "chest-row", "arnold-press":
            return .upper
        case "dead-bug", "plank", "side-plank":
            return .core
        default:
            switch ExerciseCatalog.exercise(id: id)?.bodyPart {
            case "upper legs", "lower legs": return .lower
            case "chest", "back", "shoulders", "upper arms", "lower arms", "neck": return .upper
            case "waist": return .core
            default: return .other
            }
        }
    }
}

extension WorkoutTemplate {
    // "Workout A" — the editable part of the title.
    var name: String { title.components(separatedBy: " · ").first ?? title }

    var focus: String {
        let regions = exercises.map(\.region)
        let lower = regions.filter { $0 == .lower }.count
        let upper = regions.filter { $0 == .upper }.count
        let core = regions.filter { $0 == .core }.count
        if lower + upper == 0 { return core > 0 ? "Core" : (exercises.isEmpty ? "No exercises yet" : "Mixed") }
        let smaller = Double(min(lower, upper)), both = Double(lower + upper)
        if smaller / both >= 1.0 / 3.0 { return "Full body" }
        let main = lower >= upper ? "Lower body" : "Upper body"
        return core > 0 ? main + " + core" : main
    }

    // "Workout A · Lower body + core"
    var displayTitle: String { "\(name) · \(focus)" }
}

// MARK: - Reps as a single number
// The plan's reps can be text like "10–12", "8 / leg", "30–40 s" or "RIR 2". The workout editor
// uses one number: the first number in the text (or 10 if there isn't one).
extension ExerciseTemplate {
    var repCount: Int {
        // Text that doesn't start with a number (e.g. "RIR 2") counts as 10 reps.
        guard reps.first?.isNumber == true else { return isTimed ? 30 : 10 }
        return Int(reps.prefix { $0.isNumber }) ?? (isTimed ? 30 : 10)
    }

    // "12" + what came after the number/range in the old text: "8–10 / leg" → "12 / leg".
    // Timed exercises keep their seconds: "30–40 s / side" → "45 s / side".
    static func reps(_ n: Int, keepingSuffixOf old: String, timed: Bool) -> String {
        var rest = Substring(old)
        if let first = rest.firstIndex(where: \.isNumber) {
            rest = rest[first...].drop { $0.isNumber }                       // first number
            if let dash = rest.first, dash == "–" || dash == "-" {           // "–12" of a range
                rest = rest.dropFirst().drop { $0.isNumber }
            }
        } else {
            rest = ""                                                        // e.g. "RIR 2"
        }
        var suffix = String(rest)
        if timed && !suffix.hasPrefix(" s") { suffix = " s" + suffix }
        return "\(n)" + suffix
    }
}
