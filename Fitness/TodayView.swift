import SwiftUI
import SwiftData

struct TodayView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .imperial }
    @AppStorage(PlanTemplate.overrideKey) private var overrideRaw = ""

    private var today: Date { .now }
    private var scheduled: WorkoutTemplate { PlanTemplate.scheduledWorkout(for: today) }
    private var workout: WorkoutTemplate { PlanTemplate.workout(for: today, override: overrideRaw) }
    private var isSwapped: Bool { workout.id != scheduled.id }

    // Picking the scheduled workout clears the override.
    private var selectedID: Binding<String> {
        Binding(
            get: { workout.id },
            set: { id in
                overrideRaw = id == scheduled.id ? "" : "\(PlanTemplate.dayKey(today))|\(id)"
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Today's workout", selection: selectedID) {
                        ForEach(PlanTemplate.phase1) { Text($0.id).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    if isSwapped {
                        HStack {
                            Text("Swapped for today · scheduled was \(scheduled.id)")
                            Spacer()
                            Button("Undo") { overrideRaw = "" }.font(.footnote.bold())
                        }
                    } else {
                        Text("Scheduled for today · tap A, B or C to swap")
                    }
                }

                Section {
                    ForEach(workout.exercises) { ex in
                        NavigationLink(value: ex) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ex.name).font(.headline)
                                Text("\(ex.sets) × \(ex.reps)").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
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
            if let info = ExerciseLibrary.info(for: exercise.id) {
                Section { HowToCarousel(info: info) }
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
