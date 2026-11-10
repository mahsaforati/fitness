# Fitness

iOS app (SwiftUI + SwiftData) for logging weights and reps against a 6-month home dumbbell plan.

## Status — first commit
- Four tabs: **Today** (home), Calendar, Progress, Plan
- Phase 1 of the plan built in as a template (Workouts A / B / C)
- Log weight × reps per set; weights stored in kg, shown in **lb by default** with an lb/kg switch
- Every Phase 1 exercise shows short how-to steps and what to avoid

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
- Calendar view and weekly/monthly Progress charts
- Excel (.xlsx) plan import
- Exercise demo videos (on hold)
