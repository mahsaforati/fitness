import SwiftUI
import SwiftData

struct TodayView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .imperial }
    private let workout = PlanTemplate.workout(for: .now)

    var body: some View {
        NavigationStack {
            List(workout.exercises) { ex in
                NavigationLink(value: ex) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ex.name).font(.headline)
                        Text("\(ex.sets) × \(ex.reps)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(workout.title)
            .navigationDestination(for: ExerciseTemplate.self) { ExerciseLogView(exercise: $0, units: units) }
            .toolbar {
                Picker("Units", selection: $unitsRaw) {
                    ForEach(UnitSystem.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }.pickerStyle(.segmented).frame(width: 100)
            }
        }
    }
}

struct ExerciseLogView: View {
    let exercise: ExerciseTemplate
    let units: UnitSystem
    @Environment(\.modelContext) private var context
    @State private var weights: [String]
    @State private var reps: [String]

    init(exercise: ExerciseTemplate, units: UnitSystem) {
        self.exercise = exercise
        self.units = units
        _weights = State(initialValue: Array(repeating: "", count: exercise.sets))
        _reps = State(initialValue: Array(repeating: "", count: exercise.sets))
    }

    var body: some View {
        Form {
            if !exercise.howTo.isEmpty {
                Section("How to") {
                    ForEach(Array(exercise.howTo.enumerated()), id: \.offset) { i, step in
                        Text("\(i + 1). \(step)")
                    }
                }
            }
            Section("Sets (\(units.label))") {
                ForEach(0..<exercise.sets, id: \.self) { i in
                    HStack {
                        Text("Set \(i + 1)")
                        Spacer()
                        TextField(units.label, text: $weights[i]).keyboardType(.decimalPad).frame(width: 70)
                        Text("×")
                        TextField("reps", text: $reps[i]).keyboardType(.numberPad).frame(width: 50)
                    }
                }
            }
            Button("Save sets", action: save)
        }
        .navigationTitle(exercise.name)
    }

    private func save() {
        for i in 0..<exercise.sets {
            guard let w = Double(weights[i]), let r = Int(reps[i]) else { continue }
            context.insert(SetLog(exerciseID: exercise.id, setNumber: i + 1,
                                  weightKg: units.toKg(w), reps: r))
        }
    }
}
