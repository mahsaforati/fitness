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
            .init(id: "rear-delt-fly", name: "Rear-delt fly", sets: 3, reps: "12–15"),
            .init(id: "push-up", name: "Push-ups", sets: 2, reps: "RIR 2"),
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

    static func workout(id: String) -> WorkoutTemplate? {
        phase1.first { $0.id == id }
    }

    // Mon/Tue = A, Wed/Thu = B, Fri–Sun = C.
    static func scheduledWorkout(for date: Date) -> WorkoutTemplate {
        switch Calendar.current.component(.weekday, from: date) {
        case 2, 3: return phase1[0]
        case 4, 5: return phase1[1]
        default:   return phase1[2]
        }
    }

    // MARK: Swap today's workout
    // The choice is saved with the day it was made ("2026-11-13|B"),
    // so it applies only to that day and the schedule resumes tomorrow.

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

    static func workout(for date: Date, override stored: String) -> WorkoutTemplate {
        if let id = overrideID(from: stored, on: date), let w = workout(id: id) { return w }
        return scheduledWorkout(for: date)
    }
}
