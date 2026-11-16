# Fitness

iOS app (SwiftUI + SwiftData) for logging weights and reps against a 6-month home dumbbell plan.

## Status — first commit
- Four tabs: **Today** (home), Calendar, Progress, Plan
- Phase 1 of the plan built in as a template (Workouts A / B / C)
- **Your workouts**: the dumbbell button at the end of the workout name on Today opens Workouts A, B and C, each with a preview of its exercises. Open one to see every exercise (tap for the how-to) and tap "Do this workout today" to swap; the swap lasts for that day only, and "Go back to the scheduled workout" undoes it
- Quick logging on Today: the current exercise opens with one pre-filled set and Log, then Repeat / Add; tap a logged set to adjust with − / +, swipe left to remove
- **Edit today's workout**: swipe left on an exercise (or long-press) to remove it, **Add exercise** to add any exercise from the plan; changes are saved for that day only and never change the plan (**Reset to plan** undoes them)
- **Exercise list**: Add exercise searches 1,324 exercises (filter Dumbbell + bodyweight / All equipment and by body part; ⓘ shows steps and muscles). Text from [exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset) (MIT; notice kept in `ExerciseCatalog.licenseNotice`); exercise videos © Gym visual (https://gymvisual.com/), used under licence; plan videos are bundled in `Fitness/ExerciseVideos/`, others download on first view
- **Supersets**: exercises tagged with the same `superset` in `PlanTemplate.swift` open together as one card (Workout B: Rear-delt fly + Push-ups): the exercises numbered 1, 2… each with How at the top; finished rounds as one line ("Round 1  10×12 · BW×8", swipe to remove); the current round as numbered rows with − / +; one **Log round** that saves all of them and starts the rest. An exercise with fewer sets drops out of later rounds; **Add round** after the planned rounds
- Sets save instantly (one record per set per day), a rest timer starts after each set (a thin countdown line inside the open exercise, right under its name, with −10s and +10s), and a bar shows exercises done
- **Start workout**: a grey ▶ button at the end of the workout name (next to the dumbbell) starts the workout; there's no progress bar until you tap it. Then a thick bar shows exercises done and the workout time, with Pause/Resume and Stop beside it. Stop asks first; then ▶ comes back, with "✓ Done in 42:10" under the title if every exercise was finished (▶ again clears today's sets for that workout and starts fresh). Resets each new day
- **Logging sets**: an open exercise starts with one pre-filled set (from last time, or a starting value) with − / + for weight and reps right in the row, and a **Log** button. After that, **Repeat** logs another set with the same numbers and **Add** opens a new set to change. The exercise ticks off once the plan's sets are logged; you can keep repeating after that
- Weights stored in kg, shown in **lb by default**; switch units on the Plan tab
- **Calendar**: month grid in the Figma style; days with logged sets show A/B/C, tap a day to see its sets and volume
- Every Phase 1 exercise has a swipeable how-to card: short steps + "avoid" tip, then a looping animation with worked muscles highlighted

## Run it
Option A — XcodeGen (recommended):
```
brew install xcodegen
xcodegen generate
open Fitness.xcodeproj
```
Option B — in Xcode create a new iOS App called `Fitness` (SwiftUI, SwiftData), delete the generated Swift files and drag in the `Fitness/` folder.

Requires iOS 17+.

## Next
- Weekly/monthly Progress charts
- Excel (.xlsx) plan import
- Realistic female-figure animations with muscle highlighting (replace the placeholder stick figure)
- **Timed exercises** (plank, side plank): no weight, just seconds (− / + in 5 s steps, shown as "30 s")
- **Up next goes in order**: Today shows the workout after the one you last did on an earlier day (A → B → C → A…), not by weekday. Nothing logged yet → A
- **Your workouts** list has no Today/Scheduled labels; opening one shows its exercises and a **Let's Do This!** button that makes it today's workout
- **Auto start**: logging a set when the workout isn't running does what ▶ does: starts the timer and progress bar (resumes if paused; a new timer if it was stopped, keeping your sets)
- **Edit your workouts** (Plan tab): tap a workout to see it; tap **Edit** to rename it, add / remove / drag to reorder exercises, and tap an exercise to change sets, reps (or time) and supersets. Nothing is saved until you tap **✓**; **✕** discards the changes. Saved on the iPhone; **Reset to the original plan** undoes all edits. Today and Calendar use your edited workouts
