# WorkoutTracker

iOS app (SwiftUI + SwiftData) for logging weights and reps against a 6-month home dumbbell plan.

## Status — first commit
- Four tabs: **Today** (home), Calendar, Progress, Plan
- Phase 1 of the plan built in as a template (Workouts A / B / C)
- Log weight × reps per set; weights stored in kg, shown in **lb by default** with an lb/kg switch
- Short how-to steps on the exercise screen (goblet squat so far)

## Run it
Option A — XcodeGen (recommended):
```
brew install xcodegen
xcodegen generate
open WorkoutTracker.xcodeproj
```
Option B — in Xcode create a new iOS App called `WorkoutTracker` (SwiftUI, SwiftData), delete the generated Swift files and drag in the `WorkoutTracker/` folder.

Requires iOS 17+.

## Next
- Calendar view and weekly/monthly Progress charts
- Excel (.xlsx) plan import
- How-to text for every exercise; realistic animations with highlighted muscles
