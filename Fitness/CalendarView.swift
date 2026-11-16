import SwiftUI
import SwiftData

// Calendar tab, styled after "2 · Calendar" in the Figma file.
// Only days with logged sets get a letter (A/B/C); tap a day to see what was logged.
struct CalendarView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    @AppStorage(PlanTemplate.templatesKey) private var templatesRaw = ""   // redraw when the Plan tab edits a workout
    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .imperial }
    @Query(sort: \SetLog.date) private var logs: [SetLog]

    @State private var month = CalendarView.cal.dateInterval(of: .month, for: .now)!.start
    @State private var selected = CalendarView.cal.startOfDay(for: .now)

    // Weeks start on Monday, as in the design.
    static let cal: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }()
    private var cal: Calendar { Self.cal }
    private var today: Date { cal.startOfDay(for: .now) }

    var body: some View {
        let byDay = Dictionary(grouping: logs) { cal.startOfDay(for: $0.date) }
        let doneThisMonth = byDay.keys.filter { cal.isDate($0, equalTo: month, toGranularity: .month) }.count

        // Built like Today (a List in a NavigationStack with the bar hidden) so the title sits in the same place.
        NavigationStack {
          List {
            Section { header(done: doneThisMonth) }.pageTitleRow()
            Section {
              VStack(alignment: .leading, spacing: 0) {
                weekdayHeader
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 8) {
                    ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            let dayLogs = byDay[day] ?? []
                            DayCell(day: day,
                                    letter: dayLogs.isEmpty ? nil : (Self.workout(for: dayLogs)?.id ?? "✓"),
                                    isToday: day == today,
                                    isPast: day < today,
                                    isSelected: day == selected)
                                .onTapGesture { selected = day }
                        } else {
                            Color.clear.frame(height: 50)
                        }
                    }
                }
                .padding(.top, 10)

                DayCard(day: selected, logs: byDay[selected] ?? [], units: units)
                    .padding(.top, 24)
              }
              .padding(.bottom, 24)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
          }
          .environment(\.defaultMinListRowHeight, 0)
          .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Header

    // Same title style and place as Today (see PageTitle).
    private func header(done: Int) -> some View {
        PageTitle(month.formatted(.dateTime.month(.wide).year()),
                  subtitle: "\(done) session\(done == 1 ? "" : "s") done this month") {
            HStack(spacing: 18) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.ink)
        }
    }

    private var weekdayHeader: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        let ordered = Array(symbols[first...] + symbols[..<first])
        return HStack(spacing: 5) {
            ForEach(ordered.indices, id: \.self) { i in
                Text(ordered[i])
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // Days of the month, with nil padding before the 1st so it lands on the right weekday.
    private var gridDays: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let days: [Date?] = range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: lead) + days
    }

    private func shiftMonth(_ by: Int) {
        if let m = cal.date(byAdding: .month, value: by, to: month) { month = m }
    }

    // The workout most of a day's logged exercises belong to.
    static func workout(for logs: [SetLog]) -> WorkoutTemplate? {
        // Exercises added from the big list belong to no workout, so they don't count here.
        let ids = logs.compactMap { log in
            PlanTemplate.phase1.first { $0.exercises.contains { $0.id == log.exerciseID } }?.id
        }
        let counts = Dictionary(grouping: ids) { $0 }.mapValues(\.count)
        guard let id = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return PlanTemplate.workout(id: id)
    }
}

// MARK: - Colours from the Figma file

private enum Palette {
    static let background = Color(red: 0.961, green: 0.961, blue: 0.957) // #F5F5F4
    static let card       = Color.white
    static let pastDay    = Color(red: 0.980, green: 0.980, blue: 0.976) // #FAFAF9
    static let done       = Color(red: 0.906, green: 0.898, blue: 0.894) // #E7E5E4 warm grey
    static let today      = Color(red: 0.267, green: 0.251, blue: 0.235) // #44403C dark grey outline for today
    static let ink        = Color(red: 0.110, green: 0.098, blue: 0.090) // #1C1917
    static let muted      = Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93
}

// MARK: - Day cell

private struct DayCell: View {
    let day: Date
    let letter: String?   // only set when sets were logged that day
    let isToday: Bool
    let isPast: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 14, weight: isToday ? .bold : .semibold))
                .foregroundStyle(isToday ? Palette.today : Palette.ink)
            if let letter {
                Text(letter)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(border, lineWidth: isToday ? 2 : 1.5))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted)
                            + (letter.map { ", Workout \($0) done" } ?? ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // Days with a workout are grey (today included); today gets a dark outline, the selected day a lighter one.
    private var fill: Color {
        if letter != nil { return Palette.done }
        return isPast ? Palette.pastDay : Palette.card
    }

    private var border: Color {
        if isToday { return Palette.today }
        return isSelected ? Palette.ink.opacity(0.35) : .clear
    }
}

// MARK: - Selected day card

private struct DayCard: View {
    let day: Date
    let logs: [SetLog]
    let units: UnitSystem
    @AppStorage(PlanTemplate.editsKey) private var editsRaw = ""
    @Environment(\.modelContext) private var context
    @State private var confirmingDelete = false

    private static var allExercises: [ExerciseTemplate] { PlanTemplate.phase1.flatMap(\.exercises) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                if !logs.isEmpty { dayMenu }
            }

            if logs.isEmpty {
                Text(Calendar.current.isDateInToday(day) ? "Nothing logged yet" : "No workout logged")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 8)
            } else {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(exercises, id: \.id) { ex in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(ex.name).foregroundStyle(Palette.ink)
                            Text(setsText(ex.sets)).foregroundStyle(Palette.ink.opacity(0.75))
                        }
                        .font(.system(size: 13))
                    }
                }
                .padding(.top, 16)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
        .confirmationDialog(deleteQuestion, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete \(logs.count) set\(logs.count == 1 ? "" : "s")", role: .destructive, action: deleteDay)
        } message: {
            Text("This can't be undone.")
        }
    }

    // ⋯ on the day: delete everything logged that day (asks first).
    private var dayMenu: some View {
        Menu {
            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("Delete this day's sets", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 32, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Day options")
    }

    private var deleteQuestion: String {
        "Delete \(logs.count) set\(logs.count == 1 ? "" : "s") from \(day.formatted(.dateTime.month(.abbreviated).day()))?"
    }

    private func deleteDay() {
        for log in logs { context.delete(log) }
        try? context.save()
    }

    // "Mon, Nov 9 · Workout A" (date order follows the phone's region)
    private var title: String {
        let date = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        guard let w = CalendarView.workout(for: logs) else { return date }
        return "\(date) · Workout \(w.id)"
    }

    // "6/6 exercises · volume 6,880 lb" — counted against that day's workout as edited
    // (exercises removed or added for that day), not the original plan.
    private var summary: String {
        let volume = logs.reduce(0.0) { $0 + units.display($1.weightKg) * Double($1.reps) }
        let done = exercises.count
        let count = CalendarView.workout(for: logs)
            .map { PlanTemplate.workout($0, editedOn: day, stored: editsRaw) }
            .map { "\(done)/\(max($0.exercises.count, done))" } ?? "\(done)"
        return "\(count) exercises · volume \(Int(volume.rounded()).formatted()) \(units.label)"
    }

    private struct LoggedExercise { let id: String; let name: String; let sets: [SetLog] }

    // Logged sets grouped by exercise, in plan order.
    private var exercises: [LoggedExercise] {
        let grouped = Dictionary(grouping: logs, by: \.exerciseID)
        let order = Self.allExercises.map(\.id)
        return grouped.keys
            .sorted { (order.firstIndex(of: $0) ?? .max, $0) < (order.firstIndex(of: $1) ?? .max, $1) }
            .map { id in
                LoggedExercise(id: id,
                               name: ExerciseCatalog.name(for: id),
                               sets: grouped[id]!.sorted { $0.setNumber < $1.setNumber })
            }
    }

    // "35 lb × 12, 12, 10" when the weight is the same; otherwise "35 lb × 12, 40 lb × 10".
    private func setsText(_ sets: [SetLog]) -> String {
        let weights = sets.map { format($0.weightKg) }
        if Set(weights).count == 1, let w = weights.first {
            return "\(w) \(units.label) × " + sets.map { String($0.reps) }.joined(separator: ", ")
        }
        return zip(weights, sets).map { "\($0) \(units.label) × \($1.reps)" }.joined(separator: ", ")
    }

    private func format(_ kg: Double) -> String {
        let v = (units.display(kg) * 10).rounded() / 10
        return v == v.rounded() ? String(Int(v)) : String(v)
    }
}
