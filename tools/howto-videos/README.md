# How-video generator

Makes the How-page exercise videos with Google's AI models and gets them into the app.
Every video ends up at the app's spec: **4:5, 1080 × 1350, 30 fps, one rep (~4 s) looping, HEVC, no audio, ~0.5–0.7 MB**.

How it works, per exercise:

1. **Pose** — Nano Banana (`gemini-3.1-flash-image`) draws your reference woman in the exercise's start pose, as a tall 9:16 still. The model tends to draw her top to bottom, so the script then **reframes** it: it finds her outline and shrinks her into the part of the frame the app shows clear of its buttons and title, filling in matching background around her. The original is kept as `pose-raw.jpg`.
2. **You approve the pose** (nothing is animated until you do).
3. **Video** — Gemini Omni Flash animates one rep, using the approved pose as both the first and the last frame, so the clip loops seamlessly. Omni only makes 9:16 or 16:9, so the script then crops the middle 4:5 out of it, trims it to one rep, removes the sound and encodes it to the spec.
4. **You accept the video.**
5. **Install** — accepted videos are copied into `Fitness/HowToVideos/howto-<id>.mp4`. The How page uses them automatically; exercises without one keep showing the placeholder.

## One-time setup (on your Mac)

Google's current SDK needs **Python 3.10 or newer**; the Python that comes with macOS is 3.9, which only gets an old SDK without video support. So install Homebrew's Python and give the script its own environment:

```bash
brew install ffmpeg python
cd ~/projects/fitness/tools/howto-videos
$(brew --prefix)/bin/python3 -m venv .venv
source .venv/bin/activate
pip install -U google-genai pillow
export GEMINI_API_KEY=your-ai-studio-key     # add this line to ~/.zshrc so it's always set
```

Each time you open a new Terminal window to use the script:

```bash
cd ~/projects/fitness/tools/howto-videos
source .venv/bin/activate
```

(With the environment active, `python3` below is the new Python.)

Never put the key in a file in the repo.

## The reference image

Everything depends on `reference.png`: the same woman, look and background in every video. Make it from a frame of a video you like:

```bash
python3 generate.py reference --from ../../Fitness/HowToPlaceholder.mp4 --at 0.2
```

To give her your face, add a clear photo of yourself (front-facing, good light, nothing covering your face):

```bash
python3 generate.py reference --face ~/Desktop/my-face.jpg
```

By default she gets a **resemblance** (like a relative: your face shape, hair and general look, but her own person); `--likeness medium` for a closer resemblance, `--likeness strong` to make her look like you. Add wishes with `--note "looser curls"`, and `--out reference-v2.png` to keep the current reference and save a new version next to it (copy the one you like to `reference.png`). Each run starts from the figure without a face change, so versions don't drift. Only her face and hair change; the previous figure is kept as `reference-before-face.png`. Poses made before the change still have the old face: redo them with `poses --redo`.

…or drop your own `reference.png` (a still, plain flat sage background, full body) into this folder.

## Making videos: the checklist (follow it every time)

Every step waits for you, so nothing is paid for or put in the app until you've looked at it.
`python3 generate.py status` always prints the exact next command, so if you're ever unsure where
you are, run that.

**0. Start a session** (every new Terminal window):

```bash
cd ~/projects/fitness
git checkout main && git pull            # be on main, with the latest script
cd tools/howto-videos
source .venv/bin/activate                # the newer Python (see One-time setup)
```

**1. Poses** (a still of each start position, ~seconds each):

```bash
python3 generate.py poses                       # every plan exercise that has no pose yet
python3 generate.py poses --only db-rdl plank   # or just some
```

If a lying, seated or bench exercise keeps coming out standing (the model copies the standing
reference), redo it in two steps: the pose is drawn first without the reference, then given her look:
`python3 generate.py poses --only db-bench --two-step`

**2. Check the poses**: `open out/review.html`. For each one check:
- the right start position for the exercise, holding the right equipment
- **no extra objects** (spare weights, benches she isn't using)
- her whole body is visible, nothing cut off
- the right muscles are red

Then approve the good ones and redo the bad ones:

```bash
python3 generate.py approve db-rdl plank …      # or: approve --all
python3 generate.py reject-pose step-up         # then run `poses` again: it redoes only rejected ones
```

**3. Videos** (only approved poses; ~1–2 minutes each):

```bash
python3 generate.py videos
```

If one fails after Google made it, just run `videos` again: it fetches the same video, you don't pay twice.

**4. Check the videos**: `open out/review.html` (they play there exactly as the app crops them). For each one check:
- **full range of motion** (e.g. thighs parallel in a squat, not a half rep)
- correct form, nothing on the "avoid" list
- one rep that ends where it started (the loop has no jump)
- no new objects, no text, camera doesn't move

```bash
python3 generate.py accept db-rdl plank …       # or: accept --all
python3 generate.py reject-video step-up        # then run `videos` again: it redoes only rejected ones
```

**5. Put them in the app**:

```bash
python3 generate.py install      # copies accepted videos into Fitness/HowToVideos/ and updates the Xcode project
```

Build and run in Xcode (if a video doesn't change: Product › Clean Build Folder, then run).

**6. Save them in git** so they're not only on this Mac:

```bash
cd ~/projects/fitness
git add Fitness/HowToVideos
git commit -m "How videos: <which ones>"
git push
```

## The big list (1,324 exercises)

Same commands with `--catalog`, in batches so you can check quality and cost as you go:

```bash
python3 generate.py poses --catalog --limit 100              # first 100
python3 generate.py poses --catalog --limit 100 --offset 100 # next 100
```

Don't `install` these into the app: ~800 MB is too much to ship. They're meant to be hosted (e.g. Apple-hosted Background Assets) and downloaded on first view.

## Tuning

At the top of `generate.py`:

- `POSE_PROMPT` and `VIDEO_PROMPT`: the wording sent for every exercise.
- `HEAD_MIN` / `FEET_MAX`: where the figure must sit in the 9:16 frame so the crop keeps it clear of the app's buttons and title.
- `CLIP_SECONDS`, `OUT_BITRATE`: rep length and file size.
- Model names can be changed without editing: `HOWTO_IMAGE_MODEL=… HOWTO_VIDEO_MODEL=… python3 generate.py …`.

Poses made before reframing existed, or after changing `SAFE_TOP` / `SAFE_BOTTOM` / `SAFE_SIDE`: `python3 generate.py reframe` refits them, at no API cost.

Changed the crop or size settings? `python3 generate.py crop` re-crops everything already generated, at no API cost.
