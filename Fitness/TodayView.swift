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
    // What's currently stored for today, so the button can show "Saved ✓" until something changes.
    @State private var savedWeights: [String]? = nil
    @State private var savedReps: [String]? = nil
    // Previous session's sets, keyed by set number.
    @State private var lastSession: [Int: SetLog] = [:]
    @State private var lastSessionDate: Date? = nil
    @State private var loaded = false
    @State private var saveCount = 0

    init(exercise: ExerciseTemplate, units: UnitSystem) {
        self.exercise = exercise
        self.units = units
        _weights = State(initialValue: Array(repeating: "", count: exercise.sets))
        _reps = State(initialValue: Array(repeating: "", count: exercise.sets))
    }

    private var isSaved: Bool { savedWeights == weights && savedReps == reps }

    var body: some View {
        Form {
            if let info = ExerciseLibrary.info(for: exercise.id) {
                Section { HowToCarousel(info: info) }
            }
            Section {
                ForEach(0..<exercise.sets, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Set \(i + 1)")
                            Spacer()
                            TextField(units.label, text: $weights[i]).keyboardType(.decimalPad).frame(width: 70)
                            Text("×")
                            TextField("reps", text: $reps[i]).keyboardType(.numberPad).frame(width: 50)
                        }
                        if let last = lastSession[i + 1] {
                            Text("Last time: \(format(last.weightKg)) \(units.label) × \(last.reps)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Sets (\(units.label))")
            } footer: {
                if let d = lastSessionDate {
                    Text("Last time = \(d.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            Section {
                Button(action: save) {
                    HStack {
                        Spacer()
                        if isSaved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                        } else {
                            Text("Save sets")
                        }
                        Spacer()
                    }
                }
                .disabled(isSaved)
            }
        }
        .navigationTitle(exercise.name)
        .sensoryFeedback(.success, trigger: saveCount)
        .onAppear(perform: load)
    }

    private func format(_ kg: Double) -> String {
        let v = (units.display(kg) * 10).rounded() / 10
        return v == v.rounded() ? String(Int(v)) : String(v)
    }

    private func logs(from start: Date? = nil, to end: Date? = nil) -> [SetLog] {
        let id = exercise.id
        let lower = start ?? .distantPast
        let upper = end ?? .distantFuture
        let descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.exerciseID == id && $0.date >= lower && $0.date < upper },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private var todayRange: (Date, Date) {
        let start = Calendar.current.startOfDay(for: .now)
        return (start, Calendar.current.date(byAdding: .day, value: 1, to: start)!)
    }

    // Fill in today's saved sets (if any) and the previous session's numbers.
    private func load() {
        guard !loaded else { return }
        loaded = true
        let (start, end) = todayRange

        let todays = logs(from: start, to: end)
        if !todays.isEmpty {
            for log in todays where (1...exercise.sets).contains(log.setNumber) {
                weights[log.setNumber - 1] = format(log.weightKg)
                reps[log.setNumber - 1] = String(log.reps)
            }
            savedWeights = weights
            savedReps = reps
        }

        if let latest = logs(to: start).first {
            let day = Calendar.current.startOfDay(for: latest.date)
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: day)!
            lastSessionDate = day
            for log in logs(from: day, to: dayEnd) where lastSession[log.setNumber] == nil {
                lastSession[log.setNumber] = log
            }
        }
    }

    // One record per set per day: saving again today updates those records instead of adding new ones.
    private func save() {
        let (start, end) = todayRange
        var existing: [Int: SetLog] = [:]
        for log in logs(from: start, to: end) {
            if existing[log.setNumber] == nil {
                existing[log.setNumber] = log
            } else {
                context.delete(log) // clean up duplicates from before this fix
            }
        }

        for i in 0..<exercise.sets {
            let setNumber = i + 1
            if let w = Double(weights[i]), let r = Int(reps[i]) {
                if let log = existing[setNumber] {
                    log.weightKg = units.toKg(w)
                    log.reps = r
                    log.date = .now
                } else {
                    context.insert(SetLog(exerciseID: exercise.id, setNumber: setNumber,
                                          weightKg: units.toKg(w), reps: r))
                }
            } else if let log = existing[setNumber] {
                context.delete(log) // row was cleared
            }
        }
        try? context.save()
        savedWeights = weights
        savedReps = reps
        saveCount += 1
    }
}
