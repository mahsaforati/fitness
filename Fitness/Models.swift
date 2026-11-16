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
