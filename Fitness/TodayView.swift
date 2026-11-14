import SwiftUI
import SwiftData

// Today: log every set right on this screen.
// - The exercise you're on opens up with a row per set (swipe left to remove one); finished exercises close with a ✓ and the next one opens.
// - Tap a set row to log it with last session's numbers; tap a logged row to change it (− / +).
// - "Same as last time" logs all remaining sets in one tap; "+ Add set" adds an extra set.
// - Everything saves as soon as you log it (one record per set per day), and a rest timer starts.
struct TodayView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .imperial }
    @AppStorage(PlanTemplate.overrideKey) private var overrideRaw = ""
    @AppStorage("restSeconds") private var restSeconds = 90
    @Environment(\.modelContext) private var context
    @Query(sort: \SetLog.date) private var allLogs: [SetLog]

    @State private var path: [ExerciseTemplate] = []
    @State private var expandedID: String? = nil      // nil = follow progress; "" = all closed
    @State private var extraSets: [String: Int] = [:]  // sets added (+) or removed (−) vs the plan, for today
    @State private var editing: SetEdit?
    @State private var restEnd: Date?
    @State private var logCount = 0
    @State private var restDoneCount = 0

    private var today: Date { .now }
    private var dayStart: Date { Calendar.current.startOfDay(for: .now) }
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
        let states = workout.exercises.map(state(for:))
        let doneCount = states.filter(\.done).count
        let openID = expandedID ?? states.first(where: { !$0.done })?.ex.id

        NavigationStack(path: $path) {
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
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(doneCount), total: Double(max(states.count, 1)))
                            .tint(Tone.ink)
                        Text("\(doneCount) of \(states.count) exercises done")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }

                Section {
                    ForEach(states, id: \.ex.id) { s in
                        if s.ex.id == openID {
                            expandedRows(s)
                        } else {
                            collapsedRow(s)
                        }
                    }
                }
            }
            .navigationTitle(workout.title)
            .navigationDestination(for: ExerciseTemplate.self) { ExerciseHowToView(exercise: $0) }
            .sheet(item: $editing) { e in
                SetEditor(edit: e, units: units,
                          onSave: { saveEdit($0) },
                          onDelete: { removeSet(e.exercise, e.setNumber) })
                    .presentationDetents([.height(320)])
            }
            .safeAreaInset(edge: .bottom) {
                if let end = restEnd {
                    RestBar(end: end,
                            add: { restEnd = end.addingTimeInterval(30) },
                            skip: { restEnd = nil })
                }
            }
            .task(id: restEnd) {
                guard let end = restEnd else { return }
                try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
                if !Task.isCancelled, restEnd == end {
                    restEnd = nil
                    restDoneCount += 1
                }
            }
            .sensoryFeedback(.success, trigger: logCount)
            .sensoryFeedback(.impact(weight: .heavy), trigger: restDoneCount)
            .onChange(of: workout.id) {
                expandedID = nil
                extraSets = [:]
            }
        }
    }

    // MARK: - Rows

    private func collapsedRow(_ s: ExState) -> some View {
        Button {
            withAnimation { expandedID = s.ex.id }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(s.done ? Tone.check : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.ex.name).font(.headline).foregroundStyle(Color.primary)
                    Text(collapsedSubtitle(s)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down").font(.footnote).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    // The open exercise: a header row, one row per set, then a row with "+ Add set" / "Same as last time".
    @ViewBuilder
    private func expandedRows(_ s: ExState) -> some View {
        HStack(alignment: .top) {
            Button {
                withAnimation { expandedID = "" }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.ex.name).font(.headline).foregroundStyle(Color.primary)
                    Text(planLine(s)).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if ExerciseLibrary.info(for: s.ex.id) != nil {
                Button { path.append(s.ex) } label: {
                    Text("How")
                        .font(.footnote.bold())
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(.systemGray5)))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)

        ForEach(0..<s.count, id: \.self) { i in
            setRow(s, i + 1)
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation { extraSets[s.ex.id] = s.count + 1 - s.ex.sets }
                } label: {
                    Label("Add set", systemImage: "plus").font(.subheadline).foregroundStyle(Color.primary)
                }
                .buttonStyle(.borderless)
                Spacer()
                if !s.last.isEmpty && !s.done {
                    Button { sameAsLastTime(s) } label: {
                        Text("Same as last time ✓")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color(.systemGray5)))
                    }
                    .buttonStyle(.borderless)
                }
            }
            Text("Tap a set to log it · tap a logged set to change it · swipe left to remove")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func setRow(_ s: ExState, _ n: Int) -> some View {
        let log = s.logged[n]
        let sug = suggestion(s, n)
        let value: String = log.map { setText($0.weightKg, $0.reps) } ?? (sug.known ? setText(sug.kg, sug.reps) : "Tap to enter")
        return Button {
            if let log {
                editing = SetEdit(exercise: s.ex, setNumber: n, weight: displayWeight(log.weightKg),
                                  reps: log.reps, isLogged: true)
            } else if sug.known {
                logSet(s.ex, n, kg: sug.kg, reps: sug.reps)
            } else {
                // First time: nothing to copy yet, so ask for the numbers.
                editing = SetEdit(exercise: s.ex, setNumber: n, weight: displayWeight(sug.kg),
                                  reps: sug.reps, isLogged: false)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: log != nil ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(log != nil ? Tone.check : Color.secondary.opacity(0.6))
                Text("Set \(n)")
                    .foregroundStyle(log != nil ? Tone.ink : Color.secondary)
                Spacer()
                Text(value)
                    .font(.body.weight(log != nil ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(log != nil ? Tone.ink : Color.secondary)
            }
            .padding(.leading, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .listRowBackground(log != nil ? Tone.done : Color(.secondarySystemGroupedBackground))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { removeSet(s.ex, n) }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            if log == nil {
                Button("Change before logging", systemImage: "slider.horizontal.3") {
                    editing = SetEdit(exercise: s.ex, setNumber: n, weight: displayWeight(sug.kg),
                                      reps: sug.reps, isLogged: false)
                }
            }
        }
    }

    // MARK: - Data for one exercise

    private struct ExState {
        let ex: ExerciseTemplate
        let logged: [Int: SetLog]   // today's sets by set number
        let last: [Int: SetLog]     // previous session's sets by set number
        let count: Int              // set rows shown today (plan ± added/removed sets)
        var done: Bool { (0..<count).allSatisfy { logged[$0 + 1] != nil } }
    }

    private func state(for ex: ExerciseTemplate) -> ExState {
        let start = dayStart
        let mine = allLogs.filter { $0.exerciseID == ex.id }
        var logged: [Int: SetLog] = [:]
        for log in mine where log.date >= start && logged[log.setNumber] == nil { logged[log.setNumber] = log }
        var last: [Int: SetLog] = [:]
        if let latest = mine.last(where: { $0.date < start }) {
            let day = Calendar.current.startOfDay(for: latest.date)
            for log in mine where log.date >= day && log.date < start && last[log.setNumber] == nil {
                last[log.setNumber] = log
            }
        }
        let count = max(ex.sets + extraSets[ex.id, default: 0], logged.keys.max() ?? 0, 0)
        return ExState(ex: ex, logged: logged, last: last, count: count)
    }

    // What a set row offers: last session's same set, else the set before it today,
    // else last session's last set. `known` is false when there's no history yet.
    private func suggestion(_ s: ExState, _ n: Int) -> (kg: Double, reps: Int, known: Bool) {
        if let l = s.last[n] { return (l.weightKg, l.reps, true) }
        if let p = s.logged.filter({ $0.key < n }).max(by: { $0.key < $1.key })?.value { return (p.weightKg, p.reps, true) }
        if let l = s.last.max(by: { $0.key < $1.key })?.value { return (l.weightKg, l.reps, true) }
        return (0, Int(s.ex.reps.prefix(while: \.isNumber)) ?? 10, false)
    }

    private func collapsedSubtitle(_ s: ExState) -> String {
        var parts = ["\(s.ex.sets) × \(s.ex.reps)"]
        let count = s.logged.count
        if count > 0 && !s.done { parts.append("\(count)/\(s.count) sets") }
        if let w = lastWeight(s) { parts.append(w) }
        return parts.joined(separator: " · ")
    }

    private func planLine(_ s: ExState) -> String {
        guard let w = lastWeight(s) else { return "\(s.ex.sets) × \(s.ex.reps)" }
        return "\(s.ex.sets) × \(s.ex.reps) · last time \(w)"
    }

    private func lastWeight(_ s: ExState) -> String? {
        guard let kg = s.last.values.map(\.weightKg).max(), kg > 0 else { return nil }
        return "\(format(kg)) \(units.label)"
    }

    // MARK: - Saving (every change saves right away)

    private func logSet(_ ex: ExerciseTemplate, _ n: Int, kg: Double, reps: Int, startRest: Bool = true) {
        let before = state(for: ex)
        upsert(ex.id, n, kg: kg, reps: reps)
        try? context.save()
        logCount += 1
        guard startRest else { return }
        restEnd = .now.addingTimeInterval(TimeInterval(restSeconds))
        let nowDone = (0..<before.count).allSatisfy { before.logged[$0 + 1] != nil || $0 + 1 == n }
        if !before.done && nowDone { advance(from: ex) }
    }

    private func sameAsLastTime(_ s: ExState) {
        for i in 0..<s.count where s.logged[i + 1] == nil {
            let n = i + 1
            let v = suggestion(s, n)
            upsert(s.ex.id, n, kg: v.kg, reps: v.reps)
        }
        try? context.save()
        logCount += 1
        advance(from: s.ex)
    }

    private func saveEdit(_ e: SetEdit) {
        logSet(e.exercise, e.setNumber, kg: units.toKg(e.weight), reps: e.reps, startRest: !e.isLogged)
    }

    // Remove a set row: delete its record (if logged) and renumber the sets after it.
    private func removeSet(_ ex: ExerciseTemplate, _ n: Int) {
        let s = state(for: ex)
        if let log = s.logged[n] { context.delete(log) }
        for (k, log) in s.logged where k > n { log.setNumber = k - 1 }
        extraSets[ex.id] = s.count - 1 - ex.sets
        try? context.save()
    }

    // One record per set per day: update today's record if there is one.
    private func upsert(_ exerciseID: String, _ n: Int, kg: Double, reps: Int) {
        let start = dayStart
        if let existing = allLogs.first(where: { $0.exerciseID == exerciseID && $0.setNumber == n && $0.date >= start }) {
            existing.weightKg = kg
            existing.reps = reps
        } else {
            context.insert(SetLog(exerciseID: exerciseID, setNumber: n, weightKg: kg, reps: reps))
        }
    }

    // Close the finished exercise and open the next one that isn't done.
    private func advance(from ex: ExerciseTemplate) {
        let next = workout.exercises.first { $0.id != ex.id && !state(for: $0).done }
        withAnimation { expandedID = next?.id ?? "" }
    }

    // MARK: - Formatting

    private func displayWeight(_ kg: Double) -> Double { (units.display(kg) * 10).rounded() / 10 }

    private func format(_ kg: Double) -> String {
        let v = displayWeight(kg)
        return v == v.rounded() ? String(Int(v)) : String(v)
    }

    private func setText(_ kg: Double, _ reps: Int) -> String {
        kg > 0 ? "\(format(kg)) \(units.label) × \(reps)" : "BW × \(reps)"
    }
}

// MARK: - Colours (match the Calendar / Figma)

private enum Tone {
    static let done  = Color(red: 0.890, green: 0.910, blue: 0.878) // #E3E8E0 sage
    static let check = Color(red: 0.420, green: 0.520, blue: 0.400) // darker sage for ✓
    static let ink   = Color(red: 0.110, green: 0.098, blue: 0.090) // #1C1917
}

// MARK: - Set editor (− / + for weight and reps)

struct SetEdit: Identifiable {
    let exercise: ExerciseTemplate
    let setNumber: Int
    var weight: Double   // in the units being shown
    var reps: Int
    let isLogged: Bool
    var id: String { "\(exercise.id)-\(setNumber)" }
}

struct SetEditor: View {
    @State var edit: SetEdit
    let units: UnitSystem
    let onSave: (SetEdit) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var step: Double { units == .imperial ? 5 : 2.5 }

    var body: some View {
        VStack(spacing: 20) {
            Text("\(edit.exercise.name) · Set \(edit.setNumber)").font(.headline)

            stepperRow(value: edit.weight == 0 ? "BW" : weightText, label: edit.weight == 0 ? "bodyweight" : units.label,
                       minus: { edit.weight = max(0, edit.weight - step) },
                       plus: { edit.weight += step })
            stepperRow(value: "\(edit.reps)", label: "reps",
                       minus: { edit.reps = max(0, edit.reps - 1) },
                       plus: { edit.reps += 1 })

            HStack {
                if edit.isLogged {
                    Button("Remove set", role: .destructive) { onDelete(); dismiss() }
                }
                Spacer()
                Button(edit.isLogged ? "Save" : "Log set") { onSave(edit); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.110, green: 0.098, blue: 0.090))
            }
        }
        .padding(24)
    }

    private var weightText: String {
        edit.weight == edit.weight.rounded() ? String(Int(edit.weight)) : String(format: "%.1f", edit.weight)
    }

    private func stepperRow(value: String, label: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            Button(action: minus) { Image(systemName: "minus").frame(width: 44, height: 36) }
                .buttonStyle(.bordered)
                .buttonRepeatBehavior(.enabled)
            Spacer()
            VStack(spacing: 2) {
                Text(value).font(.title2.bold()).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: plus) { Image(systemName: "plus").frame(width: 44, height: 36) }
                .buttonStyle(.bordered)
                .buttonRepeatBehavior(.enabled)
        }
        .tint(.primary)
    }
}

// MARK: - Rest timer bar

private struct RestBar: View {
    let end: Date
    let add: () -> Void
    let skip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int(end.timeIntervalSince(ctx.date).rounded(.up)))
            HStack(spacing: 12) {
                Image(systemName: "timer")
                Text("Rest \(left / 60):\(String(format: "%02d", left % 60))")
                    .font(.headline).monospacedDigit()
                Spacer()
                Button("+30s", action: add).buttonStyle(.bordered)
                Button("Skip", action: skip).buttonStyle(.bordered)
            }
            .tint(.primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - How-to page

struct ExerciseHowToView: View {
    let exercise: ExerciseTemplate

    var body: some View {
        Form {
            if let info = ExerciseLibrary.info(for: exercise.id) {
                Section { HowToCarousel(info: info) }
            }
            Section("Plan") {
                Text("\(exercise.sets) × \(exercise.reps)")
            }
        }
        .navigationTitle(exercise.name)
    }
}
