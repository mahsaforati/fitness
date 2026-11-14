import SwiftUI
import SwiftData

// Calendar tab, styled after "2 · Calendar" in the Figma file.
// Only days with logged sets get a letter (A/B/C); tap a day to see what was logged.
struct CalendarView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
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

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(done: doneThisMonth)
                weekdayHeader.padding(.top, 16)
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
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Palette.background.ignoresSafeArea())
    }

    // MARK: Header

    private func header(done: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("\(done) session\(done == 1 ? "" : "s") done this month")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            HStack(spacing: 18) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.ink)
        }
        .padding(.top, 24)
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
        let counts = Dictionary(grouping: logs) { log in
            PlanTemplate.phase1.first { $0.exercises.contains { $0.id == log.exerciseID } }?.id
        }.mapValues(\.count)
        guard let id = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return PlanTemplate.workout(id: id)
    }
}

// MARK: - Colours from the Figma file

private enum Palette {
    static let background = Color(red: 0.961, green: 0.961, blue: 0.957) // #F5F5F4
    static let card       = Color.white
    static let pastDay    = Color(red: 0.980, green: 0.980, blue: 0.976) // #FAFAF9
    static let done       = Color(red: 0.890, green: 0.910, blue: 0.878) // #E3E8E0 sage
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isToday ? Color.white : Palette.ink)
            if let letter {
                Text(letter)
                    .font(.system(size: 11))
                    .foregroundStyle(isToday ? Color.white.opacity(0.75) : Palette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Palette.ink.opacity(isSelected && !isToday ? 0.7 : 0), lineWidth: 1.5))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted)
                            + (letter.map { ", Workout \($0) done" } ?? ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if isToday { return Palette.ink }
        if letter != nil { return Palette.done }
        return isPast ? Palette.pastDay : Palette.card
    }
}

// MARK: - Selected day card

private struct DayCard: View {
    let day: Date
    let logs: [SetLog]
    let units: UnitSystem

    private static let allExercises = PlanTemplate.phase1.flatMap(\.exercises)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)

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
    }

    // "Mon, Nov 9 · Workout A" (date order follows the phone's region)
    private var title: String {
        let date = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        guard let w = CalendarView.workout(for: logs) else { return date }
        return "\(date) · Workout \(w.id)"
    }

    // "6/6 exercises · volume 6,880 lb"
    private var summary: String {
        let volume = logs.reduce(0.0) { $0 + units.display($1.weightKg) * Double($1.reps) }
        let done = exercises.count
        let count = CalendarView.workout(for: logs).map { "\(done)/\($0.exercises.count)" } ?? "\(done)"
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
                               name: Self.allExercises.first { $0.id == id }?.name ?? id,
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
