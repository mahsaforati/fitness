# Fitness

iOS app (SwiftUI + SwiftData) for logging weights and reps against a 6-month home dumbbell plan.

## Status — first commit
- Four tabs: **Today** (home), Calendar, Progress, Plan
- Phase 1 of the plan built in as a template (Workouts A / B / C)
- Swap today's workout: tap A, B or C at the top of Today; the swap lasts for that day only, then the normal schedule resumes (Undo returns to the scheduled one)
- Quick logging on Today: the current exercise opens with one row per set; tap to log last session's numbers, tap again to adjust with − / +, swipe left to remove, **+ Add set**, **Same as last time**
- Sets save instantly (one record per set per day), a rest timer starts after each set, and a bar shows exercises done
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
