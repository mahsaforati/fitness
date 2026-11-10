// Phase 1 of the 6-month plan (Excel import comes later)
import Foundation

enum PlanTemplate {
    static let phase1: [WorkoutTemplate] = [
        WorkoutTemplate(id: "A", title: "Workout A · Lower body", exercises: [
            .init(id: "goblet-squat", name: "Goblet squat", sets: 3, reps: "10–12", howTo: [
                "Hold one dumbbell vertically at your chest, elbows down.",
                "Feet shoulder-width, toes slightly out.",
                "Sit hips down and back, chest up.",
                "Go to thighs parallel, knees over toes.",
                "Drive through mid-foot to stand."]),
            .init(id: "db-rdl", name: "Dumbbell Romanian deadlift", sets: 3, reps: "10–12", howTo: []),
            .init(id: "reverse-lunge", name: "Reverse lunge", sets: 3, reps: "8 / leg", howTo: []),
            .init(id: "glute-bridge", name: "Glute bridge", sets: 3, reps: "12–15", howTo: []),
            .init(id: "lateral-walk", name: "Banded lateral walk", sets: 2, reps: "15 / side", howTo: []),
            .init(id: "dead-bug", name: "Dead bug", sets: 3, reps: "8 / side", howTo: [])
        ]),
        WorkoutTemplate(id: "B", title: "Workout B · Upper body + core", exercises: [
            .init(id: "db-bench", name: "Dumbbell bench press", sets: 3, reps: "10–12", howTo: []),
            .init(id: "one-arm-row", name: "One-arm dumbbell row", sets: 3, reps: "10–12 / side", howTo: []),
            .init(id: "seated-press", name: "Seated shoulder press", sets: 3, reps: "10", howTo: []),
            .init(id: "rear-delt-fly", name: "Rear-delt fly", sets: 3, reps: "12–15", howTo: []),
            .init(id: "push-up", name: "Push-ups", sets: 2, reps: "RIR 2", howTo: []),
            .init(id: "plank", name: "Plank", sets: 3, reps: "30–40 s", howTo: [])
        ]),
        WorkoutTemplate(id: "C", title: "Workout C · Full body", exercises: [
            .init(id: "db-deadlift", name: "Dumbbell deadlift", sets: 3, reps: "10", howTo: []),
            .init(id: "step-up", name: "Step-up", sets: 3, reps: "10 / leg", howTo: []),
            .init(id: "chest-row", name: "Incline chest-supported row", sets: 3, reps: "12", howTo: []),
            .init(id: "arnold-press", name: "Arnold press", sets: 3, reps: "10", howTo: []),
            .init(id: "hip-thrust", name: "Hip thrust", sets: 3, reps: "12", howTo: []),
            .init(id: "side-plank", name: "Side plank", sets: 3, reps: "20–30 s / side", howTo: [])
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
