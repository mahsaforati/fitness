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

    // Mon/Tue = A, Wed/Thu = B, Fri–Sun = C.
    static func workout(for date: Date) -> WorkoutTemplate {
        switch Calendar.current.component(.weekday, from: date) {
        case 2, 3: return phase1[0]
        case 4, 5: return phase1[1]
        default:   return phase1[2]
        }
    }
}
