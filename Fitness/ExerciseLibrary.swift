import SwiftUI

struct ExerciseInfo {
    let name: String
    let steps: [String]
    let avoid: String
    let muscles: [String]
    let worked: Set<BodyPart>
    var prop: Prop = .none
    var weight: WeightHold = .hand
    let start: Pose
    let end: Pose
}

// Standing, side view, arms down.
private let standing = Pose(head: P(0.50, 0.14), shoulder: P(0.50, 0.24), elbow: P(0.50, 0.38),
                            hand: P(0.51, 0.51), hip: P(0.50, 0.52), knee: P(0.50, 0.72), foot: P(0.50, 0.92))

// Standing, front view.
private let frontStand = Pose(head: P(0.50, 0.20), shoulder: P(0.50, 0.30), elbow: P(0.43, 0.43),
                              hand: P(0.42, 0.55), hip: P(0.50, 0.56), knee: P(0.46, 0.74), foot: P(0.45, 0.92),
                              elbow2: P(0.57, 0.43), hand2: P(0.58, 0.55), knee2: P(0.54, 0.74), foot2: P(0.55, 0.92))

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
            avoid: "heels lifting, knees caving in, rounding your back.",
            muscles: ["Quads", "Glutes", "Core"], worked: [.legs],
            start: Pose(head: P(0.50, 0.14), shoulder: P(0.50, 0.24), elbow: P(0.55, 0.34),
                        hand: P(0.56, 0.27), hip: P(0.50, 0.52), knee: P(0.50, 0.72), foot: P(0.50, 0.92)),
            end: Pose(head: P(0.49, 0.30), shoulder: P(0.46, 0.40), elbow: P(0.53, 0.50),
                      hand: P(0.56, 0.43), hip: P(0.36, 0.66), knee: P(0.60, 0.70), foot: P(0.50, 0.92))),

        "db-rdl": ExerciseInfo(
            name: "Dumbbell Romanian deadlift",
            steps: ["Stand tall, dumbbells in front of your thighs.",
                    "Soften your knees and keep them there.",
                    "Push hips back, sliding the weights down your legs.",
                    "Stop when you feel a hamstring stretch, back flat.",
                    "Squeeze glutes to stand back up."],
            avoid: "rounding your back, bending the knees into a squat.",
            muscles: ["Hamstrings", "Glutes", "Lower back"], worked: [.legs, .torso], weight: .both,
            start: standing,
            end: Pose(head: P(0.78, 0.36), shoulder: P(0.68, 0.38), elbow: P(0.68, 0.52),
                      hand: P(0.68, 0.64), hip: P(0.42, 0.52), knee: P(0.48, 0.72), foot: P(0.50, 0.92))),

        "reverse-lunge": ExerciseInfo(
            name: "Reverse lunge",
            steps: ["Stand tall, dumbbells at your sides.",
                    "Step one foot back and lower your back knee.",
                    "Front shin stays roughly vertical.",
                    "Push through the front heel to return.",
                    "Finish all reps, then switch legs."],
            avoid: "front knee shooting forward, leaning your torso.",
            muscles: ["Quads", "Glutes"], worked: [.legs], weight: .both,
            start: standing,
            end: Pose(head: P(0.48, 0.28), shoulder: P(0.48, 0.38), elbow: P(0.48, 0.52),
                      hand: P(0.48, 0.64), hip: P(0.48, 0.66), knee: P(0.64, 0.70), foot: P(0.62, 0.92),
                      knee2: P(0.40, 0.88), foot2: P(0.24, 0.91))),

        "glute-bridge": ExerciseInfo(
            name: "Glute bridge",
            steps: ["Lie on your back, knees bent, feet flat.",
                    "Rest a dumbbell on your hips, hold it in place.",
                    "Drive through your heels to lift your hips.",
                    "Squeeze glutes for 2 seconds at the top.",
                    "Lower slowly."],
            avoid: "arching your lower back, pushing through your toes.",
            muscles: ["Glutes", "Hamstrings"], worked: [.legs, .torso], weight: .hip,
            start: Pose(head: P(0.15, 0.87), shoulder: P(0.25, 0.88), elbow: P(0.36, 0.91),
                        hand: P(0.46, 0.86), hip: P(0.48, 0.88), knee: P(0.64, 0.70), foot: P(0.72, 0.92)),
            end: Pose(head: P(0.15, 0.87), shoulder: P(0.25, 0.88), elbow: P(0.38, 0.80),
                      hand: P(0.50, 0.66), hip: P(0.50, 0.68), knee: P(0.68, 0.66), foot: P(0.72, 0.92))),

        "lateral-walk": ExerciseInfo(
            name: "Banded lateral walk",
            steps: ["Loop a band just above your knees.",
                    "Sit into a quarter squat, chest up.",
                    "Step sideways, keeping tension on the band.",
                    "Bring the other foot in, but not all the way.",
                    "Stay low the whole time."],
            avoid: "standing up tall, letting knees cave in.",
            muscles: ["Glute medius", "Hips"], worked: [.legs], weight: .none,
            start: Pose(head: P(0.48, 0.24), shoulder: P(0.48, 0.34), elbow: P(0.42, 0.46),
                        hand: P(0.44, 0.56), hip: P(0.48, 0.60), knee: P(0.44, 0.76), foot: P(0.42, 0.92),
                        elbow2: P(0.54, 0.46), hand2: P(0.52, 0.56), knee2: P(0.53, 0.76), foot2: P(0.55, 0.92)),
            end: Pose(head: P(0.54, 0.24), shoulder: P(0.54, 0.34), elbow: P(0.48, 0.46),
                      hand: P(0.50, 0.56), hip: P(0.54, 0.60), knee: P(0.46, 0.76), foot: P(0.42, 0.92),
                      elbow2: P(0.60, 0.46), hand2: P(0.58, 0.56), knee2: P(0.64, 0.76), foot2: P(0.70, 0.92))),

        "dead-bug": ExerciseInfo(
            name: "Dead bug",
            steps: ["Lie on your back, arms straight up.",
                    "Knees bent 90°, shins parallel to the floor.",
                    "Press your lower back into the floor.",
                    "Lower opposite arm and leg slowly.",
                    "Return and switch sides."],
            avoid: "lower back lifting off the floor, rushing.",
            muscles: ["Deep core", "Abs"], worked: [.torso], weight: .none,
            start: Pose(head: P(0.15, 0.86), shoulder: P(0.25, 0.86), elbow: P(0.25, 0.72),
                        hand: P(0.25, 0.58), hip: P(0.50, 0.86), knee: P(0.50, 0.66), foot: P(0.66, 0.66)),
            end: Pose(head: P(0.15, 0.86), shoulder: P(0.25, 0.86), elbow: P(0.25, 0.72),
                      hand: P(0.25, 0.58), hip: P(0.50, 0.86), knee: P(0.50, 0.66), foot: P(0.66, 0.66),
                      elbow2: P(0.15, 0.80), hand2: P(0.05, 0.76), knee2: P(0.66, 0.82), foot2: P(0.84, 0.84))),

        // MARK: Workout B
        "db-bench": ExerciseInfo(
            name: "Dumbbell bench press",
            steps: ["Lie on the bench, feet flat on the floor.",
                    "Pull shoulder blades back and down.",
                    "Start with dumbbells beside your chest.",
                    "Press up until arms are straight.",
                    "Lower slowly, elbows at about 45°."],
            avoid: "elbows flared straight out, bouncing the weights.",
            muscles: ["Chest", "Triceps", "Front shoulders"], worked: [.arms, .torso], prop: .bench, weight: .both,
            start: Pose(head: P(0.17, 0.66), shoulder: P(0.27, 0.68), elbow: P(0.24, 0.76),
                        hand: P(0.27, 0.62), hip: P(0.55, 0.68), knee: P(0.70, 0.72), foot: P(0.72, 0.92)),
            end: Pose(head: P(0.17, 0.66), shoulder: P(0.27, 0.68), elbow: P(0.27, 0.53),
                      hand: P(0.27, 0.40), hip: P(0.55, 0.68), knee: P(0.70, 0.72), foot: P(0.72, 0.92))),

        "one-arm-row": ExerciseInfo(
            name: "One-arm dumbbell row",
            steps: ["Knee and hand on the bench, back flat.",
                    "Let the dumbbell hang under your shoulder.",
                    "Pull your elbow towards your hip.",
                    "Pause and squeeze your shoulder blade.",
                    "Lower slowly to a full stretch."],
            avoid: "twisting your torso, shrugging the shoulder.",
            muscles: ["Lats", "Upper back", "Biceps"], worked: [.arms, .torso], prop: .bench,
            start: Pose(head: P(0.23, 0.50), shoulder: P(0.33, 0.53), elbow: P(0.33, 0.66),
                        hand: P(0.33, 0.78), hip: P(0.62, 0.52), knee: P(0.62, 0.72), foot: P(0.62, 0.92),
                        elbow2: P(0.31, 0.62), hand2: P(0.30, 0.71), knee2: P(0.56, 0.71), foot2: P(0.78, 0.71)),
            end: Pose(head: P(0.23, 0.50), shoulder: P(0.33, 0.53), elbow: P(0.47, 0.44),
                      hand: P(0.43, 0.58), hip: P(0.62, 0.52), knee: P(0.62, 0.72), foot: P(0.62, 0.92),
                      elbow2: P(0.31, 0.62), hand2: P(0.30, 0.71), knee2: P(0.56, 0.71), foot2: P(0.78, 0.71))),

        "seated-press": ExerciseInfo(
            name: "Seated shoulder press",
            steps: ["Sit tall, back supported, feet flat.",
                    "Dumbbells at shoulder height, palms forward.",
                    "Press straight up until arms are nearly locked.",
                    "Lower to ears or just below.",
                    "Keep ribs down throughout."],
            avoid: "arching your lower back, clanging weights at the top.",
            muscles: ["Shoulders", "Triceps"], worked: [.arms], prop: .seat, weight: .both,
            start: Pose(head: P(0.48, 0.30), shoulder: P(0.48, 0.40), elbow: P(0.47, 0.52),
                        hand: P(0.50, 0.40), hip: P(0.48, 0.66), knee: P(0.66, 0.66), foot: P(0.68, 0.92)),
            end: Pose(head: P(0.48, 0.30), shoulder: P(0.48, 0.40), elbow: P(0.49, 0.27),
                      hand: P(0.50, 0.14), hip: P(0.48, 0.66), knee: P(0.66, 0.66), foot: P(0.68, 0.92))),

        "rear-delt-fly": ExerciseInfo(
            name: "Rear-delt fly",
            steps: ["Hinge forward with a flat back, soft knees.",
                    "Let light dumbbells hang, palms facing in.",
                    "Raise arms out to the sides, slight elbow bend.",
                    "Squeeze shoulder blades at the top.",
                    "Lower slowly."],
            avoid: "going too heavy, swinging, shrugging.",
            muscles: ["Rear shoulders", "Upper back"], worked: [.arms], weight: .both,
            start: Pose(head: P(0.50, 0.26), shoulder: P(0.50, 0.36), elbow: P(0.46, 0.48),
                        hand: P(0.48, 0.58), hip: P(0.50, 0.58), knee: P(0.45, 0.75), foot: P(0.44, 0.92),
                        elbow2: P(0.54, 0.48), hand2: P(0.52, 0.58), knee2: P(0.55, 0.75), foot2: P(0.56, 0.92)),
            end: Pose(head: P(0.50, 0.26), shoulder: P(0.50, 0.36), elbow: P(0.36, 0.38),
                      hand: P(0.22, 0.40), hip: P(0.50, 0.58), knee: P(0.45, 0.75), foot: P(0.44, 0.92),
                      elbow2: P(0.64, 0.38), hand2: P(0.78, 0.40), knee2: P(0.55, 0.75), foot2: P(0.56, 0.92))),

        "push-up": ExerciseInfo(
            name: "Push-ups",
            steps: ["Hands just wider than shoulders.",
                    "Body in one straight line, glutes tight.",
                    "Lower your chest towards the floor.",
                    "Elbows at about 45° from your body.",
                    "Push back up. Use a bench to make it easier."],
            avoid: "hips sagging, head dropping, half reps.",
            muscles: ["Chest", "Triceps", "Core"], worked: [.arms, .torso], weight: .none,
            start: Pose(head: P(0.20, 0.56), shoulder: P(0.28, 0.60), elbow: P(0.28, 0.74),
                        hand: P(0.28, 0.88), hip: P(0.56, 0.69), knee: P(0.72, 0.77), foot: P(0.88, 0.88)),
            end: Pose(head: P(0.20, 0.75), shoulder: P(0.28, 0.78), elbow: P(0.38, 0.74),
                      hand: P(0.28, 0.88), hip: P(0.56, 0.82), knee: P(0.72, 0.85), foot: P(0.88, 0.88))),

        "plank": ExerciseInfo(
            name: "Plank",
            steps: ["Forearms on the floor, elbows under shoulders.",
                    "Legs straight, up on your toes.",
                    "Squeeze glutes and brace your abs.",
                    "Keep a straight line from head to heels.",
                    "Breathe steadily and hold."],
            avoid: "hips too high or sagging, holding your breath.",
            muscles: ["Abs", "Deep core", "Shoulders"], worked: [.torso], weight: .none,
            start: Pose(head: P(0.20, 0.72), shoulder: P(0.28, 0.76), elbow: P(0.28, 0.88),
                        hand: P(0.40, 0.88), hip: P(0.56, 0.80), knee: P(0.72, 0.84), foot: P(0.88, 0.88)),
            end: Pose(head: P(0.20, 0.72), shoulder: P(0.28, 0.76), elbow: P(0.28, 0.88),
                      hand: P(0.40, 0.88), hip: P(0.56, 0.78), knee: P(0.72, 0.83), foot: P(0.88, 0.88))),

        // MARK: Workout C
        "db-deadlift": ExerciseInfo(
            name: "Dumbbell deadlift",
            steps: ["Dumbbells beside your feet, feet hip-width.",
                    "Hinge and bend knees to grip, back flat.",
                    "Brace your core, chest up.",
                    "Stand up by pushing the floor away.",
                    "Lower with control, same path."],
            avoid: "rounding your back, jerking the weight up.",
            muscles: ["Glutes", "Hamstrings", "Back", "Quads"], worked: [.legs, .torso], weight: .both,
            start: Pose(head: P(0.72, 0.40), shoulder: P(0.63, 0.45), elbow: P(0.64, 0.60),
                        hand: P(0.64, 0.76), hip: P(0.38, 0.58), knee: P(0.56, 0.72), foot: P(0.50, 0.92)),
            end: standing),

        "step-up": ExerciseInfo(
            name: "Step-up",
            steps: ["Place one whole foot on the box.",
                    "Lean slightly forward over that foot.",
                    "Drive through the heel to stand up on the box.",
                    "Lower slowly back down, same leg leading.",
                    "Finish all reps, then switch."],
            avoid: "pushing off the back foot, knee caving in.",
            muscles: ["Quads", "Glutes"], worked: [.legs], prop: .box, weight: .both,
            start: Pose(head: P(0.45, 0.16), shoulder: P(0.44, 0.26), elbow: P(0.44, 0.40),
                        hand: P(0.44, 0.52), hip: P(0.42, 0.54), knee: P(0.42, 0.73), foot: P(0.42, 0.92),
                        knee2: P(0.57, 0.62), foot2: P(0.60, 0.80)),
            end: Pose(head: P(0.60, 0.05), shoulder: P(0.60, 0.14), elbow: P(0.60, 0.28),
                      hand: P(0.60, 0.40), hip: P(0.60, 0.41), knee: P(0.52, 0.58), foot: P(0.47, 0.74),
                      knee2: P(0.60, 0.61), foot2: P(0.60, 0.80))),

        "chest-row": ExerciseInfo(
            name: "Incline chest-supported row",
            steps: ["Set the bench on an incline, lie face down.",
                    "Chest on the pad, dumbbells hanging.",
                    "Pull elbows back past your ribs.",
                    "Squeeze shoulder blades together.",
                    "Lower slowly to a full stretch."],
            avoid: "lifting your chest off the pad, shrugging.",
            muscles: ["Upper back", "Lats", "Biceps"], worked: [.arms, .torso], prop: .incline, weight: .both,
            start: Pose(head: P(0.33, 0.33), shoulder: P(0.40, 0.40), elbow: P(0.39, 0.54),
                        hand: P(0.39, 0.68), hip: P(0.64, 0.60), knee: P(0.68, 0.76), foot: P(0.78, 0.92)),
            end: Pose(head: P(0.33, 0.33), shoulder: P(0.40, 0.40), elbow: P(0.53, 0.46),
                      hand: P(0.45, 0.56), hip: P(0.64, 0.60), knee: P(0.68, 0.76), foot: P(0.78, 0.92))),

        "arnold-press": ExerciseInfo(
            name: "Arnold press",
            steps: ["Start with dumbbells at chin height, palms facing you.",
                    "Press up while rotating palms to face forward.",
                    "Finish with arms overhead.",
                    "Reverse the rotation on the way down.",
                    "Keep ribs down, core tight."],
            avoid: "arching your back, rushing the rotation.",
            muscles: ["Shoulders", "Triceps"], worked: [.arms], weight: .both,
            start: Pose(head: P(0.50, 0.20), shoulder: P(0.50, 0.30), elbow: P(0.44, 0.42),
                        hand: P(0.46, 0.30), hip: P(0.50, 0.56), knee: P(0.46, 0.74), foot: P(0.45, 0.92),
                        elbow2: P(0.56, 0.42), hand2: P(0.54, 0.30), knee2: P(0.54, 0.74), foot2: P(0.55, 0.92)),
            end: Pose(head: P(0.50, 0.20), shoulder: P(0.50, 0.30), elbow: P(0.39, 0.19),
                      hand: P(0.42, 0.06), hip: P(0.50, 0.56), knee: P(0.46, 0.74), foot: P(0.45, 0.92),
                      elbow2: P(0.61, 0.19), hand2: P(0.58, 0.06), knee2: P(0.54, 0.74), foot2: P(0.55, 0.92))),

        "hip-thrust": ExerciseInfo(
            name: "Hip thrust",
            steps: ["Upper back against the bench, feet flat.",
                    "Dumbbell on your hips, held with both hands.",
                    "Chin tucked, ribs down.",
                    "Drive hips up until your body is level.",
                    "Squeeze glutes, then lower slowly."],
            avoid: "arching your lower back, feet too far away.",
            muscles: ["Glutes", "Hamstrings"], worked: [.legs], prop: .lowBench, weight: .hip,
            start: Pose(head: P(0.22, 0.62), shoulder: P(0.30, 0.68), elbow: P(0.38, 0.77),
                        hand: P(0.46, 0.80), hip: P(0.46, 0.86), knee: P(0.66, 0.70), foot: P(0.70, 0.92)),
            end: Pose(head: P(0.22, 0.62), shoulder: P(0.30, 0.68), elbow: P(0.40, 0.62),
                      hand: P(0.52, 0.62), hip: P(0.52, 0.66), knee: P(0.70, 0.66), foot: P(0.70, 0.92))),

        "side-plank": ExerciseInfo(
            name: "Side plank",
            steps: ["Lie on your side, elbow under your shoulder.",
                    "Stack your feet, or stagger them for balance.",
                    "Lift hips so your body is in a straight line.",
                    "Top hand on your hip.",
                    "Hold, then switch sides."],
            avoid: "hips dropping, shoulder shrugging to your ear.",
            muscles: ["Obliques", "Deep core", "Hips"], worked: [.torso], weight: .none,
            start: Pose(head: P(0.22, 0.56), shoulder: P(0.28, 0.62), elbow: P(0.28, 0.88),
                        hand: P(0.38, 0.88), hip: P(0.56, 0.82), knee: P(0.72, 0.85), foot: P(0.88, 0.88),
                        elbow2: P(0.44, 0.64), hand2: P(0.56, 0.80)),
            end: Pose(head: P(0.22, 0.56), shoulder: P(0.28, 0.62), elbow: P(0.28, 0.88),
                      hand: P(0.38, 0.88), hip: P(0.56, 0.72), knee: P(0.72, 0.80), foot: P(0.88, 0.88),
                      elbow2: P(0.42, 0.58), hand2: P(0.56, 0.70)))
    ]
}
