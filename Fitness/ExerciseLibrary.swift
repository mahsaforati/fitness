import Foundation

struct ExerciseInfo {
    let name: String
    let steps: [String]
    let avoid: String
}

enum ExerciseLibrary {
    static func info(for id: String) -> ExerciseInfo? { all[id] }

    static let all: [String: ExerciseInfo] = [

        // MARK: Workout A
        "goblet-squat": ExerciseInfo(
            name: "Goblet squat",
            steps: ["Hold one dumbbell vertically at your chest, elbows down.",
                    "Feet shoulder-width, toes slightly out.",
                    "Sit hips down and back, chest up.",
                    "Go to thighs parallel, knees over toes.",
                    "Drive through mid-foot to stand."],
            avoid: "Heels lifting, knees caving in, rounding your back."),
        "db-rdl": ExerciseInfo(
            name: "Dumbbell Romanian deadlift",
            steps: ["Stand tall, dumbbells in front of your thighs.",
                    "Soften your knees and keep them there.",
                    "Push hips back, sliding the weights down your legs.",
                    "Stop when you feel a hamstring stretch, back flat.",
                    "Squeeze glutes to stand back up."],
            avoid: "Rounding your back, bending the knees into a squat."),
        "reverse-lunge": ExerciseInfo(
            name: "Reverse lunge",
            steps: ["Stand tall, dumbbells at your sides.",
                    "Step one foot back and lower your back knee.",
                    "Front shin stays roughly vertical.",
                    "Push through the front heel to return.",
                    "Finish all reps, then switch legs."],
            avoid: "Front knee shooting forward, leaning your torso."),
        "glute-bridge": ExerciseInfo(
            name: "Glute bridge",
            steps: ["Lie on your back, knees bent, feet flat.",
                    "Rest a dumbbell on your hips, hold it in place.",
                    "Drive through your heels to lift your hips.",
                    "Squeeze glutes for 2 seconds at the top.",
                    "Lower slowly."],
            avoid: "Arching your lower back, pushing through your toes."),
        "lateral-walk": ExerciseInfo(
            name: "Banded lateral walk",
            steps: ["Loop a band just above your knees.",
                    "Sit into a quarter squat, chest up.",
                    "Step sideways, keeping tension on the band.",
                    "Bring the other foot in, but not all the way.",
                    "Stay low the whole time."],
            avoid: "Standing up tall, letting knees cave in."),
        "dead-bug": ExerciseInfo(
            name: "Dead bug",
            steps: ["Lie on your back, arms straight up.",
                    "Knees bent 90°, shins parallel to the floor.",
                    "Press your lower back into the floor.",
                    "Lower opposite arm and leg slowly.",
                    "Return and switch sides."],
            avoid: "Lower back lifting off the floor, rushing."),

        // MARK: Workout B
        "db-bench": ExerciseInfo(
            name: "Dumbbell bench press",
            steps: ["Lie on the bench, feet flat on the floor.",
                    "Pull shoulder blades back and down.",
                    "Start with dumbbells beside your chest.",
                    "Press up until arms are straight.",
                    "Lower slowly, elbows at about 45°."],
            avoid: "Elbows flared straight out, bouncing the weights."),
        "one-arm-row": ExerciseInfo(
            name: "One-arm dumbbell row",
            steps: ["Knee and hand on the bench, back flat.",
                    "Let the dumbbell hang under your shoulder.",
                    "Pull your elbow towards your hip.",
                    "Pause and squeeze your shoulder blade.",
                    "Lower slowly to a full stretch."],
            avoid: "Twisting your torso, shrugging the shoulder."),
        "seated-press": ExerciseInfo(
            name: "Seated shoulder press",
            steps: ["Sit tall, back supported, feet flat.",
                    "Dumbbells at shoulder height, palms forward.",
                    "Press straight up until arms are nearly locked.",
                    "Lower to ears or just below.",
                    "Keep ribs down throughout."],
            avoid: "Arching your lower back, clanging weights at the top."),
        "rear-delt-fly": ExerciseInfo(
            name: "Rear-delt fly",
            steps: ["Hinge forward with a flat back, soft knees.",
                    "Let light dumbbells hang, palms facing in.",
                    "Raise arms out to the sides, slight elbow bend.",
                    "Squeeze shoulder blades at the top.",
                    "Lower slowly."],
            avoid: "Going too heavy, swinging, shrugging."),
        "push-up": ExerciseInfo(
            name: "Push-ups",
            steps: ["Hands just wider than shoulders.",
                    "Body in one straight line, glutes tight.",
                    "Lower your chest towards the floor.",
                    "Elbows at about 45° from your body.",
                    "Push back up. Use a bench to make it easier."],
            avoid: "Hips sagging, head dropping, half reps."),
        "plank": ExerciseInfo(
            name: "Plank",
            steps: ["Forearms on the floor, elbows under shoulders.",
                    "Legs straight, up on your toes.",
                    "Squeeze glutes and brace your abs.",
                    "Keep a straight line from head to heels.",
                    "Breathe steadily and hold."],
            avoid: "Hips too high or sagging, holding your breath."),

        // MARK: Workout C
        "db-deadlift": ExerciseInfo(
            name: "Dumbbell deadlift",
            steps: ["Dumbbells beside your feet, feet hip-width.",
                    "Hinge and bend knees to grip, back flat.",
                    "Brace your core, chest up.",
                    "Stand up by pushing the floor away.",
                    "Lower with control, same path."],
            avoid: "Rounding your back, jerking the weight up."),
        "step-up": ExerciseInfo(
            name: "Step-up",
            steps: ["Place one whole foot on the box.",
                    "Lean slightly forward over that foot.",
                    "Drive through the heel to stand up on the box.",
                    "Lower slowly back down, same leg leading.",
                    "Finish all reps, then switch."],
            avoid: "Pushing off the back foot, knee caving in."),
        "chest-row": ExerciseInfo(
            name: "Incline chest-supported row",
            steps: ["Set the bench on an incline, lie face down.",
                    "Chest on the pad, dumbbells hanging.",
                    "Pull elbows back past your ribs.",
                    "Squeeze shoulder blades together.",
                    "Lower slowly to a full stretch."],
            avoid: "Lifting your chest off the pad, shrugging."),
        "arnold-press": ExerciseInfo(
            name: "Arnold press",
            steps: ["Start with dumbbells at chin height, palms facing you.",
                    "Press up while rotating palms to face forward.",
                    "Finish with arms overhead.",
                    "Reverse the rotation on the way down.",
                    "Keep ribs down, core tight."],
            avoid: "Arching your back, rushing the rotation."),
        "hip-thrust": ExerciseInfo(
            name: "Hip thrust",
            steps: ["Upper back against the bench, feet flat.",
                    "Dumbbell on your hips, held with both hands.",
                    "Chin tucked, ribs down.",
                    "Drive hips up until your body is level.",
                    "Squeeze glutes, then lower slowly."],
            avoid: "Arching your lower back, feet too far away."),
        "side-plank": ExerciseInfo(
            name: "Side plank",
            steps: ["Lie on your side, elbow under your shoulder.",
                    "Stack your feet, or stagger them for balance.",
                    "Lift hips so your body is in a straight line.",
                    "Top hand on your hip.",
                    "Hold, then switch sides."],
            avoid: "Hips dropping, shoulder shrugging to your ear.")
    ]
}
