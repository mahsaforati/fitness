import SwiftUI
import SwiftData

// Today: log every set right on this screen.
// - The exercise you're on opens up with a row per set (swipe left to remove one); finished exercises close with a ✓ and the next one opens.
// - Tap a set row to log it with last session's numbers; tap a logged row to change it right there (− / +).
// - Start with one pre-filled set and a Log button; then Repeat logs the same numbers again and Add opens a new set to change.
// - Everything saves as soon as you log it (one record per set per day), and a rest timer starts.
struct TodayView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .imperial }
    @AppStorage(PlanTemplate.overrideKey) private var overrideRaw = ""
    @AppStorage("restSeconds") private var restSeconds = 80   // 1:20
    @AppStorage(PlanTemplate.editsKey) private var editsRaw = ""   // today's added/removed exercises
    @Environment(\.modelContext) private var context
    @Query(sort: \SetLog.date) private var allLogs: [SetLog]

    @State private var path: [ExerciseTemplate] = []
    @State private var expandedID: String? = nil      // nil = follow progress; "" = all closed
    @State private var extraSets: [String: Int] = [:]  // sets added (+) or removed (−) vs the plan, for today
    @State private var editing: SetEdit?
    @State private var restEnd: Date?
    @State private var restTotal: Double = 80   // seconds this rest started with (+10s adds to it), for the line
    @State private var restFor: String?         // the exercise the rest line shows under
    @State private var logCount = 0
    @State private var restDoneCount = 0
    @State private var showingAdd = false
    @State private var pendingRemoval: ExerciseTemplate?
    @State private var confirmingReset = false
    @State private var showingWorkouts = false
    @State private var justFinished: String?   // exercise held open for a moment before the next one opens
    // First-set numbers changed with − / + before logging (in the units shown), by exercise ID.
    private struct Draft { var weight: Double; var reps: Int }
    @State private var drafts: [String: Draft] = [:]
    // Shared with WorkoutHeader: picking another workout after finishing brings back its Start button.
    @AppStorage("workoutTimerFinished") private var timerFinished = false
    @AppStorage("workoutTimerStarted") private var timerStarted = false
    @AppStorage("workoutTimerStart") private var timerStartedAt = 0.0
    @AppStorage("workoutTimerElapsed") private var timerElapsed = 0.0

    private var today: Date { .now }
    private var dayStart: Date { Calendar.current.startOfDay(for: .now) }
    private var scheduled: WorkoutTemplate { PlanTemplate.scheduledWorkout(for: today) }
    private var planned: WorkoutTemplate { PlanTemplate.workout(for: today, override: overrideRaw) }
    private var editKey: String { PlanTemplate.editKey(today, planned.id) }
    private var dayEdit: DayEdit { PlanTemplate.edits(from: editsRaw)[editKey] ?? DayEdit() }
    // What you're doing today: the plan with today's removals/additions. The plan itself is untouched.
    private var workout: WorkoutTemplate { PlanTemplate.applying(dayEdit, to: planned) }

    // Picking the scheduled workout clears the override.
    private func pickWorkout(_ id: String) {
        overrideRaw = id == scheduled.id ? "" : "\(PlanTemplate.dayKey(today))|\(id)"
    }

    var body: some View {
        let states = workout.exercises.map(state(for:))
        let doneCount = states.filter(\.done).count
        let openID = expandedID ?? states.first(where: { !$0.done })?.ex.id

        NavigationStack(path: $path) {
            List {
                Section {
                    WorkoutHeader(title: workout.title, done: doneCount, total: states.count,
                                  showWorkouts: { showingWorkouts = true },
                                  startOver: clearTodaysSets)
                        .listRowBackground(Color.clear)
                        // Its own alignment, separate from the exercises: 12pt in from the card edges on both sides.
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                        .listRowSeparator(.hidden)
                }

                ForEach(blocks(states)) { b in
                    blockSection(b, openID: openID)
                }

                Section {
                    Button { showingAdd = true } label: {
                        Label("Add exercise", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                    }
                } footer: {
                    if !dayEdit.isEmpty {
                        HStack {
                            Text(editSummary)
                            Spacer()
                            Button("Reset to plan") { confirmingReset = true }.font(.footnote.bold())
                        }
                    }
                }
            }
            .navigationTitle(workout.title)          // used for the back button on pushed pages
            .toolbar(.hidden, for: .navigationBar)   // Today draws its own title row (with the swap button)
            .navigationDestination(for: ExerciseTemplate.self) { ExerciseHowToView(exercise: $0) }
            .sheet(isPresented: $showingWorkouts) {
                WorkoutsSheet(todayID: planned.id, scheduledID: scheduled.id, onPick: pickWorkout)
            }
            .sheet(isPresented: $showingAdd) {
                AddExerciseSheet(current: Set(workout.exercises.map(\.id)), onAdd: addExercise)
            }
            .confirmationDialog("Remove \(pendingRemoval?.name ?? "exercise") from today?",
                                isPresented: Binding(get: { pendingRemoval != nil },
                                                     set: { if !$0 { pendingRemoval = nil } }),
                                titleVisibility: .visible,
                                presenting: pendingRemoval) { ex in
                Button("Remove and delete today's sets", role: .destructive) { removeExercise(ex) }
            } message: { _ in
                Text("The sets you've logged for it today will be deleted. Your plan won't change.")
            }
            .confirmationDialog("Reset today to the plan?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { resetEdits() }
            } message: {
                Text("Removed exercises come back. Exercises you added, and any sets logged for them today, are removed.")
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
                if timerFinished { resetTimer() }   // finished one workout, now doing another
            }
        }
    }

    // MARK: - Supersets
    // The list is split into blocks: runs of normal exercises, and each superset on its own
    // section with a "Superset" header. Opening any exercise of a superset opens all of them.

    private struct Block: Identifiable {
        let tag: String?          // superset tag, nil for normal exercises
        var states: [ExState]
        var id: String { states.first?.ex.id ?? "" }
        var isSuperset: Bool { tag != nil && states.count > 1 }
    }

    private func blocks(_ states: [ExState]) -> [Block] {
        var out: [Block] = []
        for s in states {
            if let last = out.last, last.tag == s.ex.superset {
                out[out.count - 1].states.append(s)
            } else {
                out.append(Block(tag: s.ex.superset, states: [s]))
            }
        }
        return out
    }

    @ViewBuilder
    private func blockSection(_ b: Block, openID: String?) -> some View {
        let groupOpen = b.isSuperset && b.states.contains { $0.ex.id == openID }
        Section {
            ForEach(b.states, id: \.ex.id) { s in
                if s.ex.id == openID || groupOpen {
                    expandedRows(s)
                } else {
                    collapsedRow(s)
                }
            }
        } header: {
            if b.isSuperset {
                Label("Superset", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tone.ink)
            }
        } footer: {
            if b.isSuperset {
                Text("Do one set of each back to back, then rest.")
            }
        }
    }

    // MARK: - Rows

    private func collapsedRow(_ s: ExState) -> some View {
        Button {
            withAnimation { expandedID = s.ex.id; editing = nil }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(s.ex.name).font(.headline).foregroundStyle(Color.primary)
                    }
                    Text(collapsedSubtitle(s)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if s.done {
                    Image(systemName: "checkmark").font(.subheadline.bold()).foregroundStyle(Tone.check)
                        .accessibilityLabel("Done")
                } else {
                    Image(systemName: "chevron.down").font(.footnote).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { removeButton(s, iconOnly: true) }
        .contextMenu { removeButton(s) }
    }

    // Swipe shows just the trash icon (VoiceOver still reads "Remove from today"); the long-press menu keeps the text.
    private func removeButton(_ s: ExState, iconOnly: Bool = false) -> some View {
        Button { requestRemove(s) } label: {
            if iconOnly {
                Image(systemName: "trash").accessibilityLabel("Remove from today")
            } else {
                Label("Remove from today", systemImage: "trash")
            }
        }
        .tint(.red)
    }

    // The open exercise: a header row, the logged sets, then Log (first set) or Repeat / Add.
    @ViewBuilder
    private func expandedRows(_ s: ExState) -> some View {
        HStack(alignment: .top) {
            Button {
                withAnimation { expandedID = ""; editing = nil }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(s.ex.name).font(.headline).foregroundStyle(Color.primary)
                    }
                    Text(planLine(s)).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if ExerciseLibrary.info(for: s.ex.id) != nil || ExerciseCatalog.exercise(id: s.ex.id) != nil {
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { removeButton(s, iconOnly: true) }
        .contextMenu { removeButton(s) }

        // Before the first set: one pre-filled set with a Log button.
        // After that: the sets you've logged, then Repeat (same numbers again) and Add (a new set to change).
        let loggedNumbers = s.logged.keys.sorted()
        let next = (loggedNumbers.last ?? 0) + 1
        ForEach(loggedNumbers, id: \.self) { n in
            setRow(s, n)
        }
        if let end = restEnd, restFor == s.ex.id {
            RestLine(end: end, total: restTotal,
                     add: { restEnd = end.addingTimeInterval(10); restTotal += 10 },
                     skip: { withAnimation { restEnd = nil } })
                .transition(.opacity)
        }
        if let e = editing, e.exercise.id == s.ex.id, e.setNumber == next {
            setRow(s, next)   // editing a new set (from Add, or changing the first set before logging it)
        } else if loggedNumbers.isEmpty {
            firstSetRow(s)
        } else {
            repeatAddRow(s, next)
        }
    }

    // First set: weight and reps pre-filled (last time, or a starting value) with − / + right in the row,
    // then a light grey Log button.
    private func firstSetRow(_ s: ExState) -> some View {
        let sug = suggestion(s, 1)
        let id = s.ex.id
        let w = drafts[id]?.weight ?? displayWeight(sug.kg)
        let r = drafts[id]?.reps ?? sug.reps
        let step: Double = units == .imperial ? 5 : 2.5
        return HStack(spacing: 4) {
            miniButton("minus", label: "Less weight") { drafts[id] = Draft(weight: max(0, w - step), reps: r) }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(w > 0 ? format(units.toKg(w)) : "BW")
                    .font(.body.weight(.semibold)).monospacedDigit()
                if w > 0 { Text(units.label).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(minWidth: 44)
            miniButton("plus", label: "More weight") { drafts[id] = Draft(weight: w + step, reps: r) }
            Text("×").foregroundStyle(.secondary)
            miniButton("minus", label: "Fewer reps") { drafts[id] = Draft(weight: w, reps: max(1, r - 1)) }
            Text("\(r)")
                .font(.body.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 22)
            miniButton("plus", label: "More reps") { drafts[id] = Draft(weight: w, reps: r + 1) }
            Spacer(minLength: 4)
            Button {
                logSet(s.ex, 1, kg: units.toKg(w), reps: r)
                drafts[id] = nil
            } label: {
                Text("Log")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tone.ink)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Capsule().fill(Color(.systemGray5)))
            }
            .buttonStyle(.borderless)
        }
    }

    private func miniButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Tone.ink)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color(.systemGray6)))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    // Repeat logs another set with the numbers of the last one; Add opens a new set to change first.
    private func repeatAddRow(_ s: ExState, _ next: Int) -> some View {
        let last = s.logged[next - 1]
        return HStack(spacing: 10) {
            Button {
                if let last { logSet(s.ex, next, kg: last.weightKg, reps: last.reps) }
            } label: {
                Label("Repeat", systemImage: "repeat")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tone.ink)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Capsule().fill(Color(.systemGray5)))
            }
            .buttonStyle(.borderless)
            Button {
                withAnimation {
                    editing = SetEdit(exercise: s.ex, setNumber: next,
                                      weight: displayWeight(last?.weightKg ?? 0),
                                      reps: last?.reps ?? 10, isLogged: false)
                }
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tone.ink)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Capsule().fill(Color(.systemGray5)))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    // A set row, or the inline − / + editor when that set is being edited.
    @ViewBuilder
    private func setRow(_ s: ExState, _ n: Int) -> some View {
        if let e = editing, e.exercise.id == s.ex.id, e.setNumber == n {
            InlineSetEditor(edit: e, units: units,
                            onSave: { edit in withAnimation { editing = nil }; saveEdit(edit) },
                            onRemove: { withAnimation { editing = nil; if e.isLogged { removeSet(s.ex, n) } } },
                            onCancel: { withAnimation { editing = nil } })
                .id(e.id)
                .listRowBackground(Color(.secondarySystemGroupedBackground))
        } else {
            setButtonRow(s, n)
        }
    }

    private func setButtonRow(_ s: ExState, _ n: Int) -> some View {
        let log = s.logged[n]
        let sug = suggestion(s, n)
        let value: String = log.map { setText($0.weightKg, $0.reps) } ?? (sug.known ? setText(sug.kg, sug.reps) : "Tap to enter")
        return Button {
            if let log {
                withAnimation {
                    editing = SetEdit(exercise: s.ex, setNumber: n, weight: displayWeight(log.weightKg),
                                      reps: log.reps, isLogged: true)
                }
            } else if sug.known {
                logSet(s.ex, n, kg: sug.kg, reps: sug.reps)
            } else {
                // First time: nothing to copy yet, so ask for the numbers.
                withAnimation {
                    editing = SetEdit(exercise: s.ex, setNumber: n, weight: displayWeight(sug.kg),
                                      reps: sug.reps, isLogged: false)
                }
            }
        } label: {
            HStack(spacing: 12) {
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
        .listRowBackground(Color(.secondarySystemGroupedBackground))   // logged sets show in bold; no tint
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
    // else last session's last set. With no history yet it's preloaded with a starting value:
    // the plan's reps, and 10 lb (5 kg) — or bodyweight for bodyweight/band exercises.
    private func suggestion(_ s: ExState, _ n: Int) -> (kg: Double, reps: Int, known: Bool) {
        if let l = s.last[n] { return (l.weightKg, l.reps, true) }
        if let p = s.logged.filter({ $0.key < n }).max(by: { $0.key < $1.key })?.value { return (p.weightKg, p.reps, true) }
        if let l = s.last.max(by: { $0.key < $1.key })?.value { return (l.weightKg, l.reps, true) }
        let reps = Int(s.ex.reps.prefix(while: \.isNumber)) ?? 10
        return (Self.startingKg(for: s.ex, units: units), reps, true)
    }

    private static let bodyweightIDs: Set<String> = ["dead-bug", "plank", "push-up", "side-plank", "lateral-walk"]

    private static func startingKg(for ex: ExerciseTemplate, units: UnitSystem) -> Double {
        if bodyweightIDs.contains(ex.id) { return 0 }
        if let c = ExerciseCatalog.exercise(id: ex.id), c.equipment != "dumbbell" { return 0 }
        return units == .imperial ? 10 / 2.20462 : 5
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
        // In a superset, rest only once every exercise in it has done this round's set.
        if roundComplete(ex, n) {
            restTotal = Double(restSeconds)
            restFor = ex.id
            restEnd = .now.addingTimeInterval(TimeInterval(restSeconds))
        } else {
            restEnd = nil
        }
        let nowDone = (0..<before.count).allSatisfy { before.logged[$0 + 1] != nil || $0 + 1 == n }
        if !before.done && nowDone { advance(from: ex) }
    }

    private func saveEdit(_ e: SetEdit) {
        logSet(e.exercise, e.setNumber, kg: units.toKg(e.weight), reps: e.reps, startRest: !e.isLogged)
    }

    // Remove a set row: delete its record (if logged) and renumber the sets after it.
    private func removeSet(_ ex: ExerciseTemplate, _ n: Int) {
        let s = state(for: ex)
        if let log = s.logged[n] { context.delete(log) }
        for (k, log) in s.logged where k > n { log.setNumber = k - 1 }
        extraSets[ex.id] = max(0, s.count - 1 - ex.sets)   // the plan's target stays; only extra sets go
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

    // MARK: - Editing today's exercises (saved for today only, never changes the plan)

    private var editSummary: String {
        var parts: [String] = []
        if !dayEdit.removed.isEmpty { parts.append("\(dayEdit.removed.count) removed") }
        if !dayEdit.added.isEmpty { parts.append("\(dayEdit.added.count) added") }
        return "Changed for today only · " + parts.joined(separator: ", ")
    }

    private func updateEdit(_ change: (inout DayEdit) -> Void) {
        // Past days' edits are kept (a few bytes each) so the Calendar can count against what you actually did.
        var all = PlanTemplate.edits(from: editsRaw)
        var e = all[editKey] ?? DayEdit()
        change(&e)
        all[editKey] = e.isEmpty ? nil : e
        editsRaw = PlanTemplate.encode(all)
    }

    // Ask first only if sets were already logged for it today.
    private func requestRemove(_ s: ExState) {
        if s.logged.isEmpty { removeExercise(s.ex) } else { pendingRemoval = s.ex }
    }

    // Starting again after ending a workout: clear today's sets for it so every exercise is back
    // to its original state (pre-filled first set, nothing logged).
    private func clearTodaysSets() {
        withAnimation {
            for ex in workout.exercises { deleteTodaysLogs(of: ex.id) }
            extraSets = [:]
            drafts = [:]
            editing = nil
            expandedID = nil
            restEnd = nil
        }
    }

    private func resetTimer() {
        timerStartedAt = 0
        timerElapsed = 0
        timerFinished = false
        withAnimation(.easeOut(duration: 0.25)) { timerStarted = false }
    }

    private func removeExercise(_ ex: ExerciseTemplate) {
        deleteTodaysLogs(of: ex.id)
        extraSets[ex.id] = nil
        if expandedID == ex.id { expandedID = nil }
        withAnimation {
            updateEdit { e in
                if let i = e.added.firstIndex(of: ex.id) { e.added.remove(at: i) }
                else if !e.removed.contains(ex.id) { e.removed.append(ex.id) }
            }
        }
    }

    // Re-adding a planned exercise you removed puts it back in its usual place.
    private func addExercise(_ ex: ExerciseTemplate) {
        withAnimation {
            updateEdit { e in
                if let i = e.removed.firstIndex(of: ex.id) { e.removed.remove(at: i) }
                else if !e.added.contains(ex.id) { e.added.append(ex.id) }
            }
            expandedID = ex.id
        }
    }

    private func resetEdits() {
        for id in dayEdit.added { deleteTodaysLogs(of: id); extraSets[id] = nil }
        withAnimation {
            updateEdit { $0 = DayEdit() }
            expandedID = nil
        }
    }

    private func deleteTodaysLogs(of exerciseID: String) {
        let start = dayStart
        for log in allLogs where log.exerciseID == exerciseID && log.date >= start { context.delete(log) }
        try? context.save()
    }

    // True when set `n` of `ex` was the last one needed for this round of its superset
    // (every other exercise in it has set n logged, or has fewer than n sets). Always true for normal exercises.
    private func roundComplete(_ ex: ExerciseTemplate, _ n: Int) -> Bool {
        PlanTemplate.supersetGroup(of: ex, in: workout).allSatisfy { m in
            guard m.id != ex.id else { return true }
            let ms = state(for: m)
            return ms.logged[n] != nil || n > ms.count
        }
    }

    // Close the finished exercise and open the next one that isn't done
    // (another exercise in the same superset first, so the superset stays open until all of it is done).
    // An exercise just got all its sets: keep it open for 0.65 s so it's clear it's finished,
    // then slowly close it and open the next one.
    private func advance(from ex: ExerciseTemplate) {
        editing = nil
        expandedID = ex.id
        justFinished = ex.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.65))
            guard justFinished == ex.id else { return }   // something else happened meanwhile
            let partners = PlanTemplate.supersetGroup(of: ex, in: workout)
            let next = partners.first { $0.id != ex.id && !state(for: $0).done }
                ?? workout.exercises.first { $0.id != ex.id && !state(for: $0).done }
            withAnimation(.easeInOut(duration: 0.7)) {
                expandedID = next?.id ?? ""
                justFinished = nil
                if restEnd != nil, let next { restFor = next.id }   // keep resting under the exercise that's open now
            }
        }
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

// MARK: - Inline set editor (− / + for weight and reps)

struct SetEdit: Identifiable {
    let exercise: ExerciseTemplate
    let setNumber: Int
    var weight: Double   // in the units being shown
    var reps: Int
    let isLogged: Bool
    var id: String { "\(exercise.id)-\(setNumber)" }
}

// Shown in place of a set row while you change it.
struct InlineSetEditor: View {
    @State var edit: SetEdit
    let units: UnitSystem
    let onSave: (SetEdit) -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void

    private var step: Double { units == .imperial ? 5 : 2.5 }
    private let ink = Color(red: 0.110, green: 0.098, blue: 0.090)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set \(edit.setNumber)").font(.subheadline.weight(.semibold))

            stepperRow(title: "Weight",
                       value: edit.weight == 0 ? "BW" : "\(weightText) \(units.label)",
                       minus: { edit.weight = max(0, edit.weight - step) },
                       plus: { edit.weight += step })
            stepperRow(title: "Reps",
                       value: "\(edit.reps)",
                       minus: { edit.reps = max(0, edit.reps - 1) },
                       plus: { edit.reps += 1 })

            HStack(spacing: 16) {
                if edit.isLogged {
                    Button("Remove", role: .destructive, action: onRemove)
                        .buttonStyle(.borderless)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button(edit.isLogged ? "Save" : "Log set") { onSave(edit) }
                    .buttonStyle(.borderedProminent)
                    .tint(ink)
            }
            .font(.subheadline)
        }
        .padding(.leading, 8)
        .padding(.vertical, 6)
    }

    private var weightText: String {
        edit.weight == edit.weight.rounded() ? String(Int(edit.weight)) : String(format: "%.1f", edit.weight)
    }

    private func stepperRow(title: String, value: String,
                            minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button(action: minus) { Image(systemName: "minus").frame(width: 28, height: 22) }
                .buttonStyle(.bordered)
                .buttonRepeatBehavior(.enabled)
            Text(value)
                .font(.headline).monospacedDigit()
                .frame(minWidth: 64)
            Button(action: plus) { Image(systemName: "plus").frame(width: 28, height: 22) }
                .buttonStyle(.bordered)
                .buttonRepeatBehavior(.enabled)
        }
        .tint(.primary)
    }
}

// MARK: - Add an exercise to today

private struct AddExerciseSheet: View {
    let current: Set<String>                  // exercises already in today's list
    let onAdd: (ExerciseTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var homeOnly = true        // dumbbell + bodyweight only
    @State private var bodyPart = "all"
    @State private var preview: CatalogExercise?

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    // Catalog exercises matching the search and filters.
    private var matches: [CatalogExercise] {
        ExerciseCatalog.all.filter { ex in
            !current.contains(ex.id)
                && (!homeOnly || ExerciseCatalog.homeEquipment.contains(ex.equipment))
                && (bodyPart == "all" || ex.bodyPart == bodyPart)
                && (q.isEmpty || ex.name.lowercased().contains(q) || ex.target.contains(q)
                    || ex.secondary.contains { $0.contains(q) })
        }
    }

    private func planOptions(_ w: WorkoutTemplate) -> [ExerciseTemplate] {
        w.exercises.filter { !current.contains($0.id) && (q.isEmpty || $0.name.lowercased().contains(q)) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Equipment", selection: $homeOnly) {
                        Text("Dumbbell + bodyweight").tag(true)
                        Text("All equipment").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    Picker("Body part", selection: $bodyPart) {
                        Text("All").tag("all")
                        ForEach(ExerciseCatalog.bodyParts, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }

                // Your plan's exercises first (they have your animations).
                if bodyPart == "all" {
                    ForEach(PlanTemplate.phase1) { w in
                        let options = planOptions(w)
                        if !options.isEmpty {
                            Section("Your plan · \(w.title)") {
                                ForEach(options) { ex in
                                    Button { add(ex) } label: {
                                        row(ex.name, "\(ex.sets) × \(ex.reps)")
                                    }
                                }
                            }
                        }
                    }
                }

                Section("All exercises · \(matches.count)") {
                    ForEach(matches) { ex in
                        HStack {
                            Button { add(ExerciseCatalog.template(id: ex.id)) } label: {
                                row(ex.name, "\(ex.target.capitalized) · \(ex.equipment)")
                            }
                            .buttonStyle(.borderless)
                            Button { preview = ex } label: {
                                Image(systemName: "info.circle").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("How to do \(ex.name)")
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search exercises or muscles")
            .navigationTitle("Add to today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(item: $preview) { ex in
                CatalogDetailView(exercise: ex, onAdd: { add(ExerciseCatalog.template(id: ex.id)) })
            }
        }
    }

    private func row(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Color.primary)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func add(_ ex: ExerciseTemplate?) {
        guard let ex else { return }
        onAdd(ex)
        dismiss()
    }
}

// How-to for an exercise from the big list: muscles, equipment and steps (no pictures).
struct CatalogDetailView: View {
    let exercise: CatalogExercise
    var onAdd: (() -> Void)? = nil

    var body: some View {
        Form {
            Section { ExerciseVideoView(file: exercise.video) }
            Section("How to") {
                ForEach(Array(exercise.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)").font(.subheadline.bold()).monospacedDigit()
                        Text(step)
                    }
                }
            }
            Section("Muscles") {
                LabeledContent("Main", value: exercise.target.capitalized)
                if !exercise.secondary.isEmpty {
                    LabeledContent("Also works", value: exercise.secondary.map(\.capitalized).joined(separator: ", "))
                }
                LabeledContent("Equipment", value: exercise.equipment.capitalized)
            }
            if let onAdd {
                Section {
                    Button("Add to today", systemImage: "plus.circle", action: onAdd)
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Workout header: Start button, then progress bar + timer
// Before you start: one big "Start workout" button, no progress bar.
// Once started: a thick bar shows "2 of 6" and the time, with Pause/Resume and Stop beside it.
// Stop asks first, then freezes the bar at your finishing time. Long-press the bar to start over.
// The timer is saved, so it keeps going if you leave the app, and everything resets on a new day.

private struct WorkoutHeader: View {
    let title: String            // "Workout A · Lower body"
    let done: Int
    let total: Int
    let showWorkouts: () -> Void // the dumbbell button: Your workouts
    let startOver: () -> Void    // ▶ after ending: clear today's sets for this workout
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 32   // a bit larger than .title (28)

    @AppStorage("workoutTimerStart") private var startedAt = 0.0      // when it was last started; 0 = not running
    @AppStorage("workoutTimerElapsed") private var elapsed = 0.0      // seconds banked before the last start
    @AppStorage("workoutTimerDay") private var day = ""               // day the timer belongs to
    @AppStorage("workoutTimerStarted") private var started = false    // pressed Start today
    @AppStorage("workoutTimerFinished") private var finished = false  // pressed Stop today
    @State private var confirmingStop = false

    private var running: Bool { startedAt > 0 }

    private static let sage     = Color(red: 0.478, green: 0.545, blue: 0.455) // #7A8B74
    private static let sageFill = Color(red: 0.788, green: 0.820, blue: 0.773) // #C9D1C5
    private static let track    = Color(red: 0.906, green: 0.898, blue: 0.894) // #E7E5E4
    private static let stone    = Color(red: 0.267, green: 0.251, blue: 0.235) // #44403C

    // In progress = started and not stopped yet (also covers a timer started before this update).
    private var inProgress: Bool { !finished && (started || running || elapsed > 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "Workout A" with "Lower body" underneath; ▶ Start and the dumbbell at the end of the line.
            HStack(alignment: .center, spacing: 8) {
                let parts = title.components(separatedBy: " · ")
                VStack(alignment: .leading, spacing: 0) {
                    Text(parts[0])
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundStyle(Tone.ink)
                        .lineLimit(1)
                    if parts.count > 1 {
                        Text(parts.dropFirst().joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                if !inProgress {
                    roundButton("play.fill", label: "Start workout") {
                        if finished { startOver() }   // after ending: back to the original state, no question
                        start()
                    }
                        .transition(.opacity.combined(with: .scale))
                }
                roundButton("dumbbell.fill", label: "Your workouts", action: showWorkouts)
            }
            .padding(.top, 8)

            if inProgress {
                // Running or paused: the bar with the time, then pause/resume and stop.
                HStack(spacing: 8) {
                    bar
                    roundButton(running ? "pause.fill" : "play.fill",
                                label: running ? "Pause workout timer" : "Resume workout timer",
                                action: togglePause)
                    roundButton("stop.fill", label: "Stop workout") { confirmingStop = true }
                }
                .padding(.top, 12)
                .transition(.opacity)
            } else if finished && total > 0 && done >= total {
                // Stopped after finishing every exercise.
                Label("Done in \(format(elapsed))", systemImage: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tone.check)
                    .padding(.top, 6)
            }
        }
        .onAppear(perform: newDayCheck)
        .confirmationDialog("End this workout?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("End workout", role: .destructive, action: stop)
        } message: {
            Text("The timer stops at its current time. Your logged sets stay as they are.")
        }
    }

    // Grey circle button, the same style for ▶, the dumbbell, pause and stop.
    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Self.stone)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Self.track))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    // Thick bar: progress fill, "2 of 6" on the left, the time on the right.
    private var bar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ZStack(alignment: .leading) {
                Capsule().fill(Self.track)
                GeometryReader { geo in
                    Capsule().fill(Self.sageFill)
                        .frame(width: total > 0 && done > 0
                               ? max(34, geo.size.width * CGFloat(done) / CGFloat(total)) : 0)
                }
                HStack {
                    Text(finished ? "Finished · \(done) of \(total)"
                         : running ? "\(done) of \(total)" : "Paused · \(done) of \(total)")
                        .foregroundStyle(Self.stone)
                    Spacer()
                    Text(format(totalTime(at: ctx.date)))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(running || finished ? Tone.ink : Color.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
            }
            .frame(height: 36)
            .animation(.easeOut(duration: 0.3), value: done)
        }
        .contentShape(Capsule())
        .contextMenu {
            Button("Start over", systemImage: "arrow.counterclockwise", role: .destructive, action: reset)
        }
        .accessibilityElement(children: .combine)
    }

    private func totalTime(at date: Date) -> TimeInterval {
        elapsed + (running ? max(0, date.timeIntervalSince1970 - startedAt) : 0)
    }

    private func start() {
        newDayCheck()
        withAnimation(.easeOut(duration: 0.25)) { started = true }
        if finished { elapsed = 0 }   // starting again after finishing: fresh timer
        finished = false
        startedAt = Date.now.timeIntervalSince1970
    }

    private func togglePause() {
        if running {
            elapsed = totalTime(at: .now)
            startedAt = 0
        } else {
            startedAt = Date.now.timeIntervalSince1970
        }
    }

    private func stop() {
        elapsed = totalTime(at: .now)
        startedAt = 0
        finished = true
    }

    private func reset() {
        startedAt = 0
        elapsed = 0
        finished = false
        withAnimation(.easeOut(duration: 0.25)) { started = false }
    }

    // A timer left over from another day starts again from the Start button.
    private func newDayCheck() {
        let today = PlanTemplate.dayKey(.now)
        if day != today {
            reset()
            day = today
        }
    }

    // "4:05", or "1:02:09" past an hour
    private func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Rest timer bar

// A thin countdown line inside the open exercise, under the set you just logged:
// "Rest ━━━━━━── 0:52  +10s  Skip". The line empties as the rest runs down.
private struct RestLine: View {
    let end: Date
    let total: Double
    let add: () -> Void
    let skip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let left = max(0, end.timeIntervalSince(ctx.date))
            let secs = Int(left.rounded(.up))
            HStack(spacing: 10) {
                Text("Rest").font(.subheadline).foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5))
                        Capsule().fill(Color(.systemGray2))
                            .frame(width: geo.size.width * CGFloat(total > 0 ? left / total : 0))
                            .animation(.linear(duration: 0.25), value: left)
                    }
                }
                .frame(height: 4)
                Text("\(secs / 60):\(String(format: "%02d", secs % 60))")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Button("+10s", action: add)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .buttonStyle(.borderless)
                Button("Skip", action: skip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .buttonStyle(.borderless)
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - How-to page

struct ExerciseHowToView: View {
    let exercise: ExerciseTemplate

    var body: some View {
        Form {
            if let file = ExerciseCatalog.videoFile(for: exercise.id) {
                Section { ExerciseVideoView(file: file) }
            }
            if let info = ExerciseLibrary.info(for: exercise.id) {
                if ExerciseCatalog.videoFile(for: exercise.id) == nil {
                    Section { HowToCarousel(info: info) }   // no video for this one (hip thrust)
                } else {
                    Section("How to") {
                        ForEach(Array(info.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)").font(.subheadline.bold()).monospacedDigit()
                                Text(step)
                            }
                        }
                        Text("Avoid: \(info.avoid)").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Muscles") {
                        Text(info.muscles.joined(separator: " · "))
                    }
                }
            } else if let c = ExerciseCatalog.exercise(id: exercise.id) {
                Section("How to") {
                    ForEach(Array(c.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.subheadline.bold()).monospacedDigit()
                            Text(step)
                        }
                    }
                }
                Section("Muscles") {
                    LabeledContent("Main", value: c.target.capitalized)
                    LabeledContent("Equipment", value: c.equipment.capitalized)
                }
            }
            Section("Plan") {
                Text("\(exercise.sets) × \(exercise.reps)")
                if let partners = supersetPartners {
                    Label("Superset with \(partners)", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
        .navigationTitle(exercise.name)
    }

    // "Push-ups" — the other exercises in this one's superset, or nil if it isn't in one.
    private var supersetPartners: String? {
        guard exercise.superset != nil,
              let w = PlanTemplate.phase1.first(where: { $0.exercises.contains(exercise) }) else { return nil }
        let names = PlanTemplate.supersetGroup(of: exercise, in: w)
            .filter { $0.id != exercise.id }
            .map(\.name)
        return names.isEmpty ? nil : names.joined(separator: " and ")
    }
}
