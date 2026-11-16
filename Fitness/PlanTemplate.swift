// Phase 1 of the 6-month plan (Excel import comes later)
import Foundation

enum PlanTemplate {
    static let phase1: [WorkoutTemplate] = [
        WorkoutTemplate(id: "A", title: "Workout A · Lower body", exercises: [
            .init(id: "goblet-squat", name: "Goblet squat", sets: 3, reps: "10–12"),
            .init(id: "db-rdl", name: "Dumbbell Romanian deadlift", sets: 3, reps: "10–12"),
            .init(id: "reverse-lunge", name: "Reverse lunge", sets: 3, reps: "8 / leg"),
            .init(id: "glute-bridge", name: "Glute bridge", sets: 3, reps: "12–15"),
            .init(id: "lateral-walk", name: "Banded lateral walk", sets: 2, reps: "15 / side"),
            .init(id: "dead-bug", name: "Dead bug", sets: 3, reps: "8 / side")
        ]),
        WorkoutTemplate(id: "B", title: "Workout B · Upper body + core", exercises: [
            .init(id: "db-bench", name: "Dumbbell bench press", sets: 3, reps: "10–12"),
            .init(id: "one-arm-row", name: "One-arm dumbbell row", sets: 3, reps: "10–12 / side"),
            .init(id: "seated-press", name: "Seated shoulder press", sets: 3, reps: "10"),
            .init(id: "rear-delt-fly", name: "Rear-delt fly", sets: 3, reps: "12–15", superset: "B1"),
            .init(id: "push-up", name: "Push-ups", sets: 2, reps: "RIR 2", superset: "B1"),
            .init(id: "plank", name: "Plank", sets: 3, reps: "30–40 s")
        ]),
        WorkoutTemplate(id: "C", title: "Workout C · Full body", exercises: [
            .init(id: "db-deadlift", name: "Dumbbell deadlift", sets: 3, reps: "10"),
            .init(id: "step-up", name: "Step-up", sets: 3, reps: "10 / leg"),
            .init(id: "chest-row", name: "Incline chest-supported row", sets: 3, reps: "12"),
            .init(id: "arnold-press", name: "Arnold press", sets: 3, reps: "10"),
            .init(id: "hip-thrust", name: "Hip thrust", sets: 3, reps: "12"),
            .init(id: "side-plank", name: "Side plank", sets: 3, reps: "20–30 s / side")
        ])
    ]

    // The other exercises in the same superset as `ex` (in plan order, including `ex`).
    static func supersetGroup(of ex: ExerciseTemplate, in workout: WorkoutTemplate) -> [ExerciseTemplate] {
        guard let tag = ex.superset else { return [ex] }
        return workout.exercises.filter { $0.superset == tag }
    }

    static func workout(id: String) -> WorkoutTemplate? {
        phase1.first { $0.id == id }
    }

    // Mon/Tue = A, Wed/Thu = B, Fri–Sun = C.
    // Up next goes in order, not by weekday: after the last workout you logged on an earlier day
    // comes the next one (A → B → C → A…). Nothing logged yet → A.
    // Workouts logged today don't move it on until tomorrow, so today's workout stays put.
    static func scheduledWorkout(for date: Date, logs: [SetLog]) -> WorkoutTemplate {
        let dayStart = Calendar.current.startOfDay(for: date)
        let lastID = logs
            .filter { $0.date < dayStart }
            .sorted { $0.date > $1.date }
            .lazy
            .compactMap { workoutID(containing: $0.exerciseID) }
            .first
        guard let lastID, let i = phase1.firstIndex(where: { $0.id == lastID }) else { return phase1[0] }
        return phase1[(i + 1) % phase1.count]
    }

    // Which plan workout an exercise belongs to (exercises added from the library don't count).
    static func workoutID(containing exerciseID: String) -> String? {
        phase1.first { w in w.exercises.contains { $0.id == exerciseID } }?.id
    }

    // MARK: Swap today's workout
    // The choice is saved with the day it was made ("2026-11-13|B"),
    // so it applies only to that day; tomorrow the next one in order comes up.

    static let overrideKey = "workoutOverride"

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func overrideID(from stored: String, on date: Date) -> String? {
        let parts = stored.split(separator: "|").map(String.init)
        guard parts.count == 2, parts[0] == dayKey(date) else { return nil }
        return parts[1]
    }

    static func workout(for date: Date, override stored: String, logs: [SetLog]) -> WorkoutTemplate {
        if let id = overrideID(from: stored, on: date), let w = workout(id: id) { return w }
        return scheduledWorkout(for: date, logs: logs)
    }
}

// MARK: - Edit today's workout
// Exercises removed from / added to one day's workout. Saved under the day and workout
// ("2026-11-14|A"), so the plan itself never changes and the next session starts from the plan again.

struct DayEdit: Codable, Equatable {
    var removed: [String] = []   // planned exercise IDs taken out today
    var added: [String] = []     // exercise IDs added today, in the order they were added
    var isEmpty: Bool { removed.isEmpty && added.isEmpty }
}

extension PlanTemplate {
    static let editsKey = "todayEdits"

    // Every exercise in the plan, once each — what can be added to a day.
    static let allExercises: [ExerciseTemplate] = {
        var seen = Set<String>()
        return phase1.flatMap(\.exercises).filter { seen.insert($0.id).inserted }
    }()

    static func editKey(_ date: Date, _ workoutID: String) -> String { "\(dayKey(date))|\(workoutID)" }

    static func edits(from stored: String) -> [String: DayEdit] {
        (try? JSONDecoder().decode([String: DayEdit].self, from: Data(stored.utf8))) ?? [:]
    }

    static func encode(_ edits: [String: DayEdit]) -> String {
        guard let data = try? JSONEncoder().encode(edits) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    // A workout as it was on `date`, with that day's edits (if any) applied.
    static func workout(_ w: WorkoutTemplate, editedOn date: Date, stored: String) -> WorkoutTemplate {
        applying(edits(from: stored)[editKey(date, w.id)], to: w)
    }

    // The planned workout with today's removals and additions applied.
    // Added exercises go at the end and keep their superset: added exercises from the same
    // superset are placed next to each other, so adding both halves gives you the superset.
    static func applying(_ edit: DayEdit?, to w: WorkoutTemplate) -> WorkoutTemplate {
        guard let edit, !edit.isEmpty else { return w }
        let kept = w.exercises.filter { !edit.removed.contains($0.id) }
        let added = edit.added
            .compactMap { id in allExercises.first { $0.id == id } ?? ExerciseCatalog.template(id: id) }
            .filter { a in !kept.contains { $0.id == a.id } }
        var extra: [ExerciseTemplate] = []
        for ex in added where !extra.contains(where: { $0.id == ex.id }) {
            if let tag = ex.superset {
                // Put this one and every other added exercise from its superset here, in plan order.
                extra += added.filter { $0.superset == tag }.sorted { planIndex($0) < planIndex($1) }
            } else {
                extra.append(ex)
            }
        }
        return WorkoutTemplate(id: w.id, title: w.title, exercises: kept + extra)
    }

    private static func planIndex(_ ex: ExerciseTemplate) -> Int {
        allExercises.firstIndex { $0.id == ex.id } ?? .max
    }
}
